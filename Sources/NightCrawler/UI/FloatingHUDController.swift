import Cocoa
import SwiftUI

@MainActor
final class FloatingHUDController {
    private var panel: NSPanel?
    private var detailPanel: NSPanel?
    private var settingsWindow: NSWindow?
    private let store: UsageStore

    private let defaultsEdgeKey = "hudEdge"
    private let defaultsFrameKey = "hudFrame"

    private let pillWidth: CGFloat = Design.px(186)

    init(store: UsageStore) {
        self.store = store
    }

    func show() {
        guard panel == nil else { return }

        let content = HUDView(
            onSelect: { [weak self] reading in
                if reading.status.isError {
                    Task { await self?.store.refresh(providerId: reading.providerId) }
                }
                self?.showDetail(for: reading)
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
        panel.level = .floating
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
        settingsWindow?.close()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 400),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "NightCrawler Settings"
        window.contentViewController = NSHostingController(rootView: SettingsView().environmentObject(store))
        window.center()
        window.makeKeyAndOrderFront(nil)
        settingsWindow = window
    }

    private func showDetail(for reading: UsageReading) {
        detailPanel?.close()

        let hosting = NSHostingController(rootView: DetailPanelView(reading: reading) { [weak self] in
            self?.detailPanel?.close()
            self?.detailPanel = nil
        })
        hosting.preferredContentSize = NSSize(width: 260, height: 180)

        let detail = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 180),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        detail.level = .floating
        detail.backgroundColor = .clear
        detail.isOpaque = false
        detail.hasShadow = true
        detail.contentViewController = hosting
        detail.collectionBehavior = [.canJoinAllSpaces, .stationary]

        if let panel {
            positionDetail(detail, relativeTo: panel)
        }

        detail.orderFrontRegardless()
        detailPanel = detail
    }

    private func positionDetail(_ detail: NSPanel, relativeTo panel: NSPanel) {
        let panelFrame = panel.frame
        let detailSize = detail.frame.size
        let screen = NSScreen.main?.visibleFrame ?? .zero

        var origin: NSPoint
        switch edge {
        case .right:
            origin = NSPoint(x: panelFrame.minX - detailSize.width - 8, y: panelFrame.midY - detailSize.height / 2)
        case .left:
            origin = NSPoint(x: panelFrame.maxX + 8, y: panelFrame.midY - detailSize.height / 2)
        case .top:
            origin = NSPoint(x: panelFrame.midX - detailSize.width / 2, y: panelFrame.minY - detailSize.height - 8)
        case .bottom:
            origin = NSPoint(x: panelFrame.midX - detailSize.width / 2, y: panelFrame.maxY + 8)
        }

        origin.x = max(screen.minX, min(origin.x, screen.maxX - detailSize.width))
        origin.y = max(screen.minY, min(origin.y, screen.maxY - detailSize.height))
        detail.setFrameOrigin(origin)
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
