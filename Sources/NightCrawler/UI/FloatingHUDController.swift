import Cocoa
import SwiftUI

@MainActor
final class FloatingHUDController {
    private var panel: NSPanel?
    private var detailPanel: NSPanel?
    private var settingsWindow: NSWindow?
    private let store: UsageStore
    private var selectedProviderId: String?

    private let defaultsEdgeKey = "hudEdge"
    private let defaultsFrameKey = "hudFrame"

    private let pillWidth: CGFloat = Design.px(186)
    private let tailWidth: CGFloat = 12
    private let detailPanelWidth: CGFloat = 260
    private let detailPanelHeight: CGFloat = 180

    init(store: UsageStore) {
        self.store = store
    }

    func show() {
        guard panel == nil else { return }

        let content = HUDView(
            selectedProviderId: selectedProviderId,
            onSelect: { [weak self] reading in
                self?.toggleDetail(for: reading)
            },
            onSettings: { [weak self] in
                self?.showSettings()
            }
        ).environmentObject(store)
        let hosting = NSHostingController(rootView: content)
        hosting.preferredContentSize = NSSize(width: pillWidth, height: 400)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: pillWidth, height: 400),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentViewController = hosting
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]

        self.panel = panel

        if let saved = savedFrame(), let screen = screenContaining(saved.origin) {
            panel.setFrame(saved, display: false)
            self.edge = inferEdge(from: saved, on: screen)
        } else {
            positionPanel(panel, edge: edge, screen: NSScreen.main)
        }

        panel.orderFrontRegardless()
    }

    func hide() {
        detailPanel?.close()
        detailPanel = nil
        settingsWindow?.close()
        settingsWindow = nil
        if let frame = panel?.frame {
            saveFrame(frame)
        }
        panel?.close()
        panel = nil
    }

    var edge: ScreenEdge {
        get {
            ScreenEdge(rawValue: UserDefaults.standard.string(forKey: defaultsEdgeKey) ?? "") ?? .right
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsEdgeKey)
            guard let panel else { return }
            positionPanel(panel, edge: newValue, screen: NSScreen.main)
        }
    }

    func cycleEdge() {
        let all: [ScreenEdge] = [.right, .left, .top, .bottom]
        guard let index = all.firstIndex(of: edge) else { return }
        edge = all[(index + 1) % all.count]
    }

    func showSettings() {
        if let window = settingsWindow, window.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 400),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "NightCrawler Settings"
        window.contentViewController = NSHostingController(rootView: SettingsView().environmentObject(store))
        window.center()
        settingsWindow = window

        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func toggleDetail(for reading: UsageReading) {
        if selectedProviderId == reading.providerId, detailPanel != nil {
            selectedProviderId = nil
            closeDetail()
            return
        }

        selectedProviderId = reading.providerId
        if reading.status.isError {
            Task { await store.refresh(providerId: reading.providerId) }
        }
        showDetail(for: reading)
    }

    private func closeDetail() {
        detailPanel?.close()
        detailPanel = nil
    }

    private func showDetail(for reading: UsageReading) {
        closeDetail()

        let hosting = NSHostingController(rootView: DetailPanelView(reading: reading) { [weak self] in
            self?.selectedProviderId = nil
            self?.closeDetail()
        })
        hosting.preferredContentSize = NSSize(width: detailPanelWidth, height: detailPanelHeight)

        let detail = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: detailPanelWidth, height: detailPanelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        detail.level = .floating
        detail.backgroundColor = .clear
        detail.isOpaque = false
        detail.hasShadow = false
        detail.contentViewController = hosting
        detail.collectionBehavior = [.canJoinAllSpaces, .stationary]

        if let panel {
            positionDetail(detail, relativeTo: panel)
        }

        detail.orderFront(nil)
        detailPanel = detail
    }

    private func positionDetail(_ detail: NSPanel, relativeTo panel: NSPanel) {
        guard let selectedProviderId,
              let index = store.readings.firstIndex(where: { $0.providerId == selectedProviderId }) else {
            positionDetailCentered(detail, relativeTo: panel)
            return
        }

        let iconY = iconCenterY(fromTop: index)
        let panelFrame = panel.frame
        let screen = NSScreen.main?.visibleFrame ?? .zero

        let screenIconY = panelFrame.maxY - iconY
        let detailSize = detail.frame.size

        var origin = NSPoint(
            x: panelFrame.minX + tailWidth - detailSize.width,
            y: screenIconY - detailSize.height / 2
        )

        origin.y = max(screen.minY + 8, min(origin.y, screen.maxY - detailSize.height - 8))
        detail.setFrameOrigin(origin)
    }

    private func positionDetailCentered(_ detail: NSPanel, relativeTo panel: NSPanel) {
        let panelFrame = panel.frame
        let detailSize = detail.frame.size
        let screen = NSScreen.main?.visibleFrame ?? .zero

        var origin = NSPoint(
            x: panelFrame.minX - detailSize.width - 8,
            y: panelFrame.midY - detailSize.height / 2
        )
        origin.x = max(screen.minX, min(origin.x, screen.maxX - detailSize.width))
        origin.y = max(screen.minY, min(origin.y, screen.maxY - detailSize.height))
        detail.setFrameOrigin(origin)
    }

    private func iconCenterY(fromTop index: Int) -> CGFloat {
        let padTop = Design.px(69.5)
        let ringDiameter = Design.px(117)
        let ringLabelGap = Design.px(26.9)
        let percentHeight = Design.px(27)
        let cellExtent = ringDiameter + ringLabelGap + percentHeight
        let cellSpacing = Design.px(83.5)
        return padTop + ringDiameter / 2 + CGFloat(index) * (cellExtent + cellSpacing)
    }

    private func positionPanel(_ panel: NSPanel, edge: ScreenEdge, screen: NSScreen?) {
        guard let screen = screen ?? NSScreen.main else { return }
        let frame = screen.visibleFrame
        let size = panel.frame.size
        let origin: NSPoint
        switch edge {
        case .right:
            origin = NSPoint(x: frame.maxX - pillWidth, y: frame.midY - size.height / 2)
        case .left:
            origin = NSPoint(x: frame.minX, y: frame.midY - size.height / 2)
        case .top:
            origin = NSPoint(x: frame.midX - size.width / 2, y: frame.maxY - size.height)
        case .bottom:
            origin = NSPoint(x: frame.midX - size.width / 2, y: frame.minY)
        }
        panel.setFrameOrigin(origin)
    }

    private func saveFrame(_ frame: NSRect) {
        UserDefaults.standard.set(NSStringFromRect(frame), forKey: defaultsFrameKey)
    }

    private func savedFrame() -> NSRect? {
        guard let string = UserDefaults.standard.string(forKey: defaultsFrameKey) else { return nil }
        let rect = NSRectFromString(string)
        return rect.isEmpty ? nil : rect
    }

    private func screenContaining(_ point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { NSPointInRect(point, $0.frame) }
    }

    private func inferEdge(from frame: NSRect, on screen: NSScreen) -> ScreenEdge {
        let visible = screen.visibleFrame
        let midX = frame.midX
        let midY = frame.midY
        let distLeft = midX - visible.minX
        let distRight = visible.maxX - midX
        let distBottom = midY - visible.minY
        let distTop = visible.maxY - midY
        let minDist = min(distLeft, distRight, distBottom, distTop)
        switch minDist {
        case distLeft: return .left
        case distRight: return .right
        case distTop: return .top
        default: return .bottom
        }
    }

    enum ScreenEdge: String, CaseIterable {
        case left, right, top, bottom
    }
}
