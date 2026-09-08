import AppKit
import Foundation
import SwiftUI
import Testing
@testable import NightCrawler

// Physical-click coverage for the provider rings. These tests host the real
// FloatingHUDController panel and push synthesized left-mouse events through
// NSWindow.sendEvent, so they exercise the same NSHostingView hit-testing a
// user's pointer does. Accessibility is used only to read each button's frame
// for coordinates; AX performPress and direct state forcing are not proof.

@MainActor
struct HUDClickHarness {
    static let edgeKey = "hudEdge"
    /// Fraction of the ring radius that lands inside the track but outside the
    /// glyph frame and both usage arcs: px(33) of the px(58.5) radius sits
    /// between the glyph's px(23) half-side and the track's px(43) inner edge.
    static let holeFraction: CGFloat = 33 / 58.5

    let store: UsageStore
    let controller: FloatingHUDController
    let panel: NSWindow
    let host: NSView
    let edge: NotchEdge
    private let suiteName: String
    private let defaults: UserDefaults
    private let previousEdge: String?

    init(edge: NotchEdge, mini: Bool) throws {
        let app = NSApplication.shared
        let existing = Set(app.windows.map(ObjectIdentifier.init))
        suiteName = "NightCrawlerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        previousEdge = UserDefaults.standard.string(forKey: Self.edgeKey)
        UserDefaults.standard.set(edge.rawValue, forKey: Self.edgeKey)
        self.edge = edge

        // Seed the suite so the rail holds exactly the two live readings:
        // routing placeholders off, both providers enabled.
        let routingTools = RoutingToolState.defaults.map {
            RoutingToolState(id: $0.id, label: $0.label, enabled: false, available: $0.available)
        }
        defaults.set(try JSONEncoder().encode(routingTools), forKey: "routingToolStates")
        defaults.set(["claude", "codex"], forKey: "enabledProviderIds")
        store = UsageStore(providers: [], defaults: defaults)
        store.setDemoMode(true, readings: Self.readings)
        try #require(store.orderedReadings.map(\.providerId) == ["claude", "codex"])

        controller = FloatingHUDController(store: store, defaults: defaults)
        controller.show()
        controller.setMiniModeEnabled(mini)
        panel = try #require(app.windows.first { !existing.contains(ObjectIdentifier($0)) })
        host = try #require(panel.contentView?.subviews.first)
        pump(0.3)
    }

    func tearDown() {
        controller.hide()
        if let previousEdge {
            UserDefaults.standard.set(previousEdge, forKey: Self.edgeKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.edgeKey)
        }
        defaults.removePersistentDomain(forName: suiteName)
    }

    /// Two live providers with low fractions, so both usage arcs stay near
    /// 12 o'clock and the 9 o'clock hole point has nothing drawn under it.
    /// Claude's glyph has ink at its centre; the OpenAI knot is hollow there.
    static var readings: [UsageReading] {
        let now = Date()
        return [
            UsageReading(
                providerId: "claude", label: "Claude Code", accountId: "t", authMode: "subscription", source: "test",
                windows: [
                    UsageWindow(id: "weekly_scoped", label: "Fable", used: 20, limit: 100, usedPercent: 20, windowMinutes: 10080, resetsAt: now),
                    UsageWindow(id: "weekly_all", label: "All models", used: 30, limit: 100, usedPercent: 30, windowMinutes: 10080, resetsAt: now),
                ],
                status: .live, observedAt: now, error: nil
            ),
            UsageReading(
                providerId: "codex", label: "Codex CLI", accountId: "t", authMode: "subscription", source: "test",
                windows: [
                    UsageWindow(id: "primary", label: "Current session", used: 10, limit: 100, usedPercent: 10, windowMinutes: 300, resetsAt: now),
                ],
                status: .live, observedAt: now, error: nil
            ),
        ]
    }

    var railScale: CGFloat {
        HUDLayout.railScale(
            miniMode: controller.isMiniModeEnabled,
            isHovered: controller.surface.mode != .idle,
            fitScale: 1
        )
    }

    /// Ring centre in window coordinates. The hosting view publishes no
    /// accessibility children in-process, so this follows HUDLayout: every
    /// cell here is live, so each ring sits at the top of a uniform cell with
    /// its percentage label below, and Mini compaction scales the rail about
    /// its screen-edge anchor exactly as HUDRootView does.
    func ringCenter(_ providerId: String) throws -> CGPoint {
        let index = try #require(store.orderedReadings.firstIndex { $0.providerId == providerId })
        let cellCount = store.orderedReadings.count
        let slack = HUDLayout.slack(for: edge)
        let railCenter = slack + HUDLayout.shapeLength(cellCount: cellCount, edge: edge) / 2
        let bodyDepth = HUDLayout.bodyDepth(for: edge)
        let along = slack + HUDLayout.ringCenter(index: index, edge: edge)
        let across: CGFloat
        switch edge {
        case .right, .left: across = bodyDepth / 2
        case .top: across = HUDLayout.sideBodyDepth / 2
        case .bottom: across = bodyDepth - HUDLayout.sideBodyDepth / 2
        }
        let scale = railScale
        let local = NotchPlacement(edge: edge, panelSize: host.bounds.size).point(
            along: railCenter + (along - railCenter) * scale,
            across: across * scale
        )
        return host.convert(local, to: nil)
    }

    /// A point inside the ring circle at 9 o'clock with no drawn pixels under it.
    func holePoint(_ providerId: String) throws -> CGPoint {
        let center = try ringCenter(providerId)
        let offset = HUDLayout.ringDiameter / 2 * Self.holeFraction * railScale
        return CGPoint(x: center.x - offset, y: center.y)
    }

    func mouseDown(at point: CGPoint) -> NSEvent {
        NSEvent.mouseEvent(
            with: .leftMouseDown, location: point, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        )!
    }

    /// Whether the view under `point` takes a click while the panel is not key,
    /// the way a user clicking the rail from another app does.
    func acceptsFirstMouse(at point: CGPoint) -> Bool {
        let event = mouseDown(at: point)
        let container = host.superview!
        let target = host.hitTest(container.convert(point, from: nil)) ?? host
        return target.acceptsFirstMouse(for: event)
    }

    func click(_ point: CGPoint) {
        let down = mouseDown(at: point)
        panel.sendEvent(down)
        pump(0.05)
        let up = NSEvent.mouseEvent(
            with: .leftMouseUp, location: point, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 0
        )!
        panel.sendEvent(up)
        pump(0.4)
    }

    func pump(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }
}

// The controller reads its edge from UserDefaults.standard, so the cases must
// not run concurrently against one another.
@Suite(.serialized)
@MainActor
struct NativeHitTestingTests {

    /// The smallest lock: the real ProviderIcon inside the real plain Button,
    /// hosted alone, clicked with ordinary window events.
    @Test(arguments: ["claude", "codex"])
    func providerButtonTakesClicksAcrossTheWholeRing(providerId: String) throws {
        let reading = try #require(HUDClickHarness.readings.first { $0.providerId == providerId })
        var fired = 0
        let side: CGFloat = 120
        let host = NSHostingView(rootView:
            Button(action: { fired += 1 }) { ProviderIcon(reading: reading) }
                .buttonStyle(.plain)
                .frame(width: side, height: side)
        )
        host.frame = NSRect(x: 0, y: 0, width: side, height: side)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.close() }
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))

        // The ring sits above its percentage label inside the centred cell.
        let cell = HUDLayout.ringDiameter + HUDLayout.ringLabelGap + HUDLayout.percentLineHeight
        let center = host.convert(CGPoint(x: side / 2, y: (side - cell) / 2 + HUDLayout.ringDiameter / 2), to: nil)
        let radius = HUDLayout.ringDiameter / 2
        let hole = radius * HUDClickHarness.holeFraction
        let probes: [(String, CGPoint)] = [
            ("centre", center),
            ("9 o'clock", CGPoint(x: center.x - hole, y: center.y)),
            ("3 o'clock", CGPoint(x: center.x + hole, y: center.y)),
            ("6 o'clock", CGPoint(x: center.x, y: center.y - hole)),
        ]
        for (name, point) in probes {
            let before = fired
            let time = ProcessInfo.processInfo.systemUptime
            window.sendEvent(NSEvent.mouseEvent(
                with: .leftMouseDown, location: point, modifierFlags: [], timestamp: time,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!)
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            window.sendEvent(NSEvent.mouseEvent(
                with: .leftMouseUp, location: point, modifierFlags: [], timestamp: time,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!)
            RunLoop.main.run(until: Date().addingTimeInterval(0.15))
            #expect(fired == before + 1, "\(providerId) ring \(name) must fire the button once")
        }
        let outside = CGPoint(x: center.x - radius - 4, y: center.y)
        let before = fired
        let time = ProcessInfo.processInfo.systemUptime
        window.sendEvent(NSEvent.mouseEvent(
            with: .leftMouseDown, location: outside, modifierFlags: [], timestamp: time,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!)
        window.sendEvent(NSEvent.mouseEvent(
            with: .leftMouseUp, location: outside, modifierFlags: [], timestamp: time,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!)
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        #expect(fired == before, "\(providerId): just outside the ring must not fire; no giant hit rectangle")
    }

    @Test(arguments: NotchEdge.allCases)
    func harnessDeliversPhysicalClicksToAnInkedGlyphCentre(edge: NotchEdge) throws {
        let hud = try HUDClickHarness(edge: edge, mini: false)
        defer { hud.tearDown() }

        #expect(hud.acceptsFirstMouse(at: try hud.holePoint("claude")),
                "\(edge): the rail must take the first click from another app (panel key: \(hud.panel.isKeyWindow))")
        hud.click(try hud.ringCenter("claude"))
        #expect(hud.controller.surface.mode == .detail(providerId: "claude"),
                "\(edge): the Claude glyph has ink at its centre; this is the harness control")
        hud.click(try hud.ringCenter("claude"))
        #expect(hud.controller.surface.mode == .idle)
    }

    @Test(arguments: NotchEdge.allCases)
    func wholeRingCircleOpensSwitchesAndClosesDetail(edge: NotchEdge) throws {
        let hud = try HUDClickHarness(edge: edge, mini: false)
        defer { hud.tearDown() }

        hud.click(try hud.ringCenter("codex"))
        #expect(hud.controller.surface.mode == .detail(providerId: "codex"),
                "\(edge): the OpenAI knot is hollow at its centre; the ring must still take the click")
        hud.click(try hud.ringCenter("codex"))
        #expect(hud.controller.surface.mode == .idle)

        hud.click(try hud.holePoint("codex"))
        #expect(hud.controller.surface.mode == .detail(providerId: "codex"),
                "\(edge): click inside the codex ring must open its details")

        hud.click(try hud.holePoint("claude"))
        #expect(hud.controller.surface.mode == .detail(providerId: "claude"),
                "\(edge): clicking another provider's ring must switch details")

        hud.click(try hud.holePoint("claude"))
        #expect(hud.controller.surface.mode == .idle,
                "\(edge): clicking the open provider's ring again must close details")
    }

    @Test(arguments: NotchEdge.allCases)
    func miniRailAcceptsRingClicksCompactAndExpanded(edge: NotchEdge) throws {
        let hud = try HUDClickHarness(edge: edge, mini: true)
        defer { hud.tearDown() }

        #expect(hud.railScale == HUDLayout.compactRailScale)
        hud.click(try hud.holePoint("codex"))
        #expect(hud.controller.surface.mode == .detail(providerId: "codex"),
                "\(edge): compact Mini ring interior must open details")

        #expect(hud.railScale == 1, "an open card holds the Mini rail expanded")
        hud.click(try hud.holePoint("claude"))
        #expect(hud.controller.surface.mode == .detail(providerId: "claude"),
                "\(edge): expanded Mini ring interior must switch details")

        hud.click(try hud.holePoint("claude"))
        #expect(hud.controller.surface.mode == .idle,
                "\(edge): expanded Mini ring interior must close details")
    }
}
