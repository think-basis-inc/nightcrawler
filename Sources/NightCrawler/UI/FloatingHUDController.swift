import Cocoa
import QuartzCore
import SwiftUI

@MainActor
final class FloatingHUDController: ObservableObject {
    private var panel: NSPanel?
    private var hostingController: NSHostingController<AnyView>?
    private let store: UsageStore
    private let displayPreferences: HUDDisplayPreferences
    @Published var surface = HUDSurfaceState()
    @Published private(set) var isMiniModeEnabled: Bool
    @Published private(set) var isAutoHideEnabled: Bool
    @Published private var isExternallyHovered = false
    private var mouseMonitor: Any?
    private var keyMonitor: Any?
    private var globalMouseMoveMonitor: Any?
    private var localMouseMoveMonitor: Any?
    private var readingsWatch: Task<Void, Never>?
    private var pointerWatch: Task<Void, Never>?
    private var pendingHide: Task<Void, Never>?
    private var globalHotKey: GlobalHotKey?
    private var normalFrame: CGRect?
    private var isRevealed = true

    private let defaultsEdgeKey = "hudEdge"

    init(store: UsageStore, defaults: UserDefaults = .standard) {
        self.store = store
        let displayPreferences = HUDDisplayPreferences(defaults: defaults)
        self.displayPreferences = displayPreferences
        self.isMiniModeEnabled = displayPreferences.isMiniModeEnabled
        self.isAutoHideEnabled = displayPreferences.isAutoHideEnabled
    }

    func show() {
        guard panel == nil else { return }

        let baseSize = HUDLayout.panelSize(cellCount: max(store.orderedReadings.count, 1), edge: edge)
        let size = baseSize
        let hosting = NSHostingController(rootView: rootView(baseSize: baseSize))
        hostingController = hosting
        let panel = HUDPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovable = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true

        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.autoresizingMask = [.width, .height]
        hosting.view.frame = container.bounds
        hosting.view.autoresizingMask = [.width, .height]
        container.addSubview(hosting.view)
        panel.contentView = container

        self.panel = panel
        relocate()
        panel.orderFrontRegardless()
        installMonitors()
        updatePointerWatch()
        globalHotKey = GlobalHotKey { [weak self] in
            self?.toggleRevealFromHotKey()
        }
        watchReadings()
    }

    func hide() {
        readingsWatch?.cancel()
        pointerWatch?.cancel()
        cancelPendingHide()
        readingsWatch = nil
        pointerWatch = nil
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let globalMouseMoveMonitor { NSEvent.removeMonitor(globalMouseMoveMonitor) }
        if let localMouseMoveMonitor { NSEvent.removeMonitor(localMouseMoveMonitor) }
        mouseMonitor = nil
        keyMonitor = nil
        globalMouseMoveMonitor = nil
        localMouseMoveMonitor = nil
        globalHotKey = nil
        panel?.close()
        panel = nil
        hostingController = nil
    }

    var edge: NotchEdge {
        get { NotchEdge(rawValue: UserDefaults.standard.string(forKey: defaultsEdgeKey) ?? "") ?? .right }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsEdgeKey)
            relocate()
        }
    }

    func cycleEdge() {
        let all = NotchEdge.allCases
        guard let index = all.firstIndex(of: edge) else { return }
        edge = all[(index + 1) % all.count]
    }

    func showSettings() {
        reveal(animated: true)
        surface.toggleSettings()
        relocate()
    }

    func setMiniModeEnabled(_ enabled: Bool) {
        guard isMiniModeEnabled != enabled else { return }
        isMiniModeEnabled = enabled
        displayPreferences.setMiniModeEnabled(enabled)
        relocate()
    }

    func setAutoHideEnabled(_ enabled: Bool) {
        guard isAutoHideEnabled != enabled else { return }
        isAutoHideEnabled = enabled
        displayPreferences.setAutoHideEnabled(enabled)
        cancelPendingHide()
        isRevealed = true
        relocate(animated: true)
        updatePointerWatch()
    }

    func handleHUDHover(_ isHovering: Bool) {
        guard isAutoHideEnabled else { return }
        cancelPendingHide()
        if isHovering {
            reveal(animated: true)
        } else {
            scheduleHide(after: .milliseconds(350))
        }
    }

    private func toggleDetail(for reading: UsageReading) {
        reveal(animated: true)
        surface.selectProvider(reading.providerId)
        if reading.status.isError, surface.selectedProviderId == reading.providerId {
            Task { await store.refresh(providerId: reading.providerId) }
        }
        relocate()
    }

    private func relocate(animated: Bool = false) {
        guard panel != nil else { return }
        let count = max(store.orderedReadings.count, 1)
        let baseSize = HUDLayout.panelSize(cellCount: count, edge: edge)
        let size = baseSize
        let screen = NSScreen.main
        let normalFrame: CGRect
        if let screen {
            normalFrame = NotchGeometry.panelFrame(
                for: screen,
                panelSize: size,
                edge: edge,
                cellCount: count
            )
        } else {
            normalFrame = NSRect(origin: .zero, size: size)
        }
        self.normalFrame = normalFrame
        let target = isAutoHideEnabled && !isRevealed
            ? HUDVisibilityGeometry.hiddenFrame(normalFrame, edge: edge, retraction: retractionDistance)
            : normalFrame
        setPanelFrame(target, animated: animated)
        refreshRoot()
    }

    private func refreshRoot() {
        guard let hostingController else { return }
        let count = max(store.orderedReadings.count, 1)
        let baseSize = HUDLayout.panelSize(cellCount: count, edge: edge)
        hostingController.rootView = rootView(baseSize: baseSize)
    }

    private func rootView(baseSize: CGSize) -> AnyView {
        let root = HUDRootView(
            surface: Binding(
                get: { self.surface },
                set: { self.surface = $0 }
            ),
            isExternallyHovered: Binding(
                get: { self.isExternallyHovered },
                set: { self.isExternallyHovered = $0 }
            ),
            edge: edge,
            isMiniModeEnabled: isMiniModeEnabled,
            isAutoHideEnabled: isAutoHideEnabled,
            railFitScale: currentRailFitScale,
            onSelect: { [weak self] reading in
                self?.toggleDetail(for: reading)
            },
            onSettings: { [weak self] in
                self?.showSettings()
            },
            onEdgeChange: { [weak self] edge in
                self?.edge = edge
            },
            onMiniModeChange: { [weak self] enabled in
                self?.setMiniModeEnabled(enabled)
            },
            onAutoHideChange: { [weak self] enabled in
                self?.setAutoHideEnabled(enabled)
            },
            onHoverChange: { [weak self] isHovering in
                self?.handleHUDHover(isHovering)
            },
            onDismiss: { [weak self] in
                self?.surface.dismiss()
                self?.relocate()
            }
        )
        .environmentObject(store)
        .frame(width: baseSize.width, height: baseSize.height)
        return AnyView(root)
    }

    private var currentRailFitScale: CGFloat {
        guard let screen = panel?.screen ?? NSScreen.main else { return 1 }
        let availableLength = edge.isVertical
            ? screen.visibleFrame.height
            : screen.visibleFrame.width
        return HUDLayout.railFitScale(
            cellCount: max(store.orderedReadings.count, 1),
            edge: edge,
            availableLength: availableLength
        )
    }

    private func watchReadings() {
        readingsWatch?.cancel()
        readingsWatch = Task { [weak self] in
            guard let self else { return }
            var lastCount = store.orderedReadings.count
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(400))
                let count = store.orderedReadings.count
                if count != lastCount {
                    lastCount = count
                    surface.preserveAcrossRefresh()
                    relocate()
                }
            }
        }
    }

    private func installMonitors() {
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handleOutsideClick(event)
            }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                MainActor.assumeIsolated {
                    self?.surface.dismiss()
                    self?.relocate()
                }
                return nil
            }
            return event
        }
        globalMouseMoveMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handlePointerMotion(at: NSEvent.mouseLocation)
            }
        }
        localMouseMoveMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handlePointerMotion(at: NSEvent.mouseLocation)
            }
            return event
        }
    }

    private func handleOutsideClick(_ event: NSEvent) {
        guard let panel, surface.mode != .idle else { return }
        let screenPoint = NSEvent.mouseLocation
        if !panel.frame.contains(screenPoint) {
            surface.dismiss()
            relocate()
        }
    }

    private var retractionDistance: CGFloat {
        HUDLayout.bodyDepth(for: edge) + 1
    }

    private var revealedInteractionDepth: CGFloat {
        let baseDepth = HUDLayout.bodyDepth(for: edge)
        switch surface.mode {
        case .idle:
            return baseDepth
        case .detail(let id):
            let windowCount = store.orderedReadings
                .first(where: { $0.providerId == id })?
                .windows.count ?? 1
            let cardDepth = edge.isVertical
                ? HUDLayout.cardWidth
                : HUDLayout.cardHeight(windowCount: max(windowCount, 1))
            return baseDepth + HUDLayout.tailLength + cardDepth
        case .settings:
            let cardDepth = edge.isVertical
                ? HUDLayout.cardWidth
                : HUDLayout.settingsCardHeight(
                    providerCount: store.providerCatalog.count,
                    routingToolCount: store.routingToolStates.count
                )
            return baseDepth + HUDLayout.tailLength + cardDepth
        }
    }

    private func handlePointerMotion(at point: CGPoint) {
        guard isAutoHideEnabled, let screen = panel?.screen ?? NSScreen.main else { return }
        if isRevealed {
            if HUDVisibilityGeometry.shouldRetract(
                point: point,
                screenFrame: screen.visibleFrame,
                edge: edge,
                revealedDepth: revealedInteractionDepth
            ) {
                scheduleHide(after: .milliseconds(350))
            } else {
                cancelPendingHide()
            }
            return
        }
        let zone = HUDVisibilityGeometry.activationZone(in: screen.visibleFrame, edge: edge, thickness: 4)
        if zone.contains(point) {
            reveal(animated: true)
        }
    }

    private func reveal(animated: Bool) {
        cancelPendingHide()
        guard !isRevealed else { return }
        isRevealed = true
        relocate(animated: animated)
    }

    private func scheduleHide(after delay: Duration) {
        guard pendingHide == nil else { return }
        pendingHide = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, self.isAutoHideEnabled else { return }
            self.pendingHide = nil
            self.surface.dismiss()
            self.isRevealed = false
            self.relocate(animated: true)
        }
    }

    private func toggleRevealFromHotKey() {
        guard isAutoHideEnabled else { return }
        cancelPendingHide()
        if isRevealed {
            surface.dismiss()
            isRevealed = false
            relocate(animated: true)
        } else {
            reveal(animated: true)
            scheduleHide(after: .seconds(4))
        }
    }

    private func setPanelFrame(_ frame: CGRect, animated: Bool) {
        guard let panel else { return }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard animated, !reduceMotion else {
            panel.setFrame(frame, display: true)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
            panel.animator().setFrame(frame, display: true)
        }
    }

    private func updatePointerWatch() {
        pointerWatch?.cancel()
        pointerWatch = nil
        guard isAutoHideEnabled else { return }
        pointerWatch = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled, let self else { return }
                self.handlePointerMotion(at: NSEvent.mouseLocation)
            }
        }
    }

    private func cancelPendingHide() {
        pendingHide?.cancel()
        pendingHide = nil
    }
}

/// Borderless panels otherwise refuse keyboard focus, leaving settings fields inert.
private final class HUDPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
