import Cocoa
import SwiftUI

@MainActor
final class FloatingHUDController {
    private var panel: NSPanel?
    private let store: UsageStore
    private var edge: ScreenEdge = .right

    init(store: UsageStore) {
        self.store = store
    }

    func show() {
        guard panel == nil else { return }

        let content = HUDView().environmentObject(store)
        let hosting = NSHostingController(rootView: content)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 60, height: 400),
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
        positionPanel(panel)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.close()
        panel = nil
    }

    private func positionPanel(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let size = panel.frame.size

        let origin: NSPoint
        switch edge {
        case .right:
            origin = NSPoint(x: frame.maxX - size.width - 8, y: frame.midY - size.height / 2)
        case .left:
            origin = NSPoint(x: frame.minX + 8, y: frame.midY - size.height / 2)
        case .top:
            origin = NSPoint(x: frame.midX - size.width / 2, y: frame.maxY - size.height - 8)
        case .bottom:
            origin = NSPoint(x: frame.midX - size.width / 2, y: frame.minY + 8)
        }
        panel.setFrameOrigin(origin)
    }

    enum ScreenEdge {
        case left, right, top, bottom
    }
}
