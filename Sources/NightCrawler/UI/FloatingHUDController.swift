import Cocoa
import SwiftUI

@MainActor
final class FloatingHUDController: ObservableObject {
    private var panel: NSPanel?
    private let store: UsageStore
    @Published var surface = HUDSurfaceState()
    private var mouseMonitor: Any?
    private var keyMonitor: Any?
    private var readingsWatch: Task<Void, Never>?

    private let defaultsEdgeKey = "hudEdge"

    init(store: UsageStore) {
        self.store = store
    }

    func show() {
        guard panel == nil else { return }

        let hosting = NSHostingController(rootView: HUDRootView(
            surface: Binding(
                get: { self.surface },
                set: { self.surface = $0 }
            ),
            edge: edge,
            onSelect: { [weak self] reading in
                self?.toggleDetail(for: reading)
            },
            onSettings: { [weak self] in
                self?.showSettings()
            },
            onEdgeChange: { [weak self] edge in
                self?.edge = edge
            },
            onDismiss: { [weak self] in
                self?.surface.dismiss()
                self?.relocate()
            }
        ).environmentObject(store))

        let size = HUDLayout.panelSize(cellCount: max(store.orderedReadings.count, 1), edge: edge)
        let panel = NSPanel(
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
        watchReadings()
    }

    func hide() {
        readingsWatch?.cancel()
        readingsWatch = nil
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        mouseMonitor = nil
        keyMonitor = nil
        panel?.close()
        panel = nil
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
        surface.toggleSettings()
        relocate()
    }

    private func toggleDetail(for reading: UsageReading) {
        surface.selectProvider(reading.providerId)
        if reading.status.isError, surface.selectedProviderId == reading.providerId {
            Task { await store.refresh(providerId: reading.providerId) }
        }
        relocate()
    }

    private func relocate() {
        guard let panel else { return }
        let count = max(store.orderedReadings.count, 1)
        let size = HUDLayout.panelSize(cellCount: count, edge: edge)
        let screen = NSScreen.main
        let frame: CGRect
        if let screen {
            frame = NotchGeometry.panelFrame(for: screen, panelSize: size, edge: edge)
        } else {
            frame = NSRect(origin: .zero, size: size)
        }
        panel.setFrame(frame, display: true)
        refreshRoot()
    }

    private func refreshRoot() {
        guard let panel, let container = panel.contentView else { return }
        container.subviews.forEach { $0.removeFromSuperview() }
        let hosting = NSHostingController(rootView: HUDRootView(
            surface: Binding(
                get: { self.surface },
                set: { self.surface = $0 }
            ),
            edge: edge,
            onSelect: { [weak self] reading in
                self?.toggleDetail(for: reading)
            },
            onSettings: { [weak self] in
                self?.showSettings()
            },
            onEdgeChange: { [weak self] edge in
                self?.edge = edge
            },
            onDismiss: { [weak self] in
                self?.surface.dismiss()
                self?.relocate()
            }
        ).environmentObject(store))
        hosting.view.frame = container.bounds
        hosting.view.autoresizingMask = [.width, .height]
        container.addSubview(hosting.view)
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
    }

    private func handleOutsideClick(_ event: NSEvent) {
        guard let panel, surface.mode != .idle else { return }
        let screenPoint = NSEvent.mouseLocation
        if !panel.frame.contains(screenPoint) {
            surface.dismiss()
            relocate()
        }
    }
}
