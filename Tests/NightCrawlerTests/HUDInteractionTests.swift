import AppKit
import Foundation
import SwiftUI
import Testing
@testable import NightCrawler

@Test
func miniAndAutoHidePreferencesPersistAcrossRestart() {
    let suiteName = "NightCrawlerTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let first = HUDDisplayPreferences(defaults: defaults)
    #expect(first.isMiniModeEnabled == false)
    #expect(first.isAutoHideEnabled == false)

    first.setMiniModeEnabled(true)
    first.setAutoHideEnabled(true)

    let restarted = HUDDisplayPreferences(defaults: defaults)
    #expect(restarted.isMiniModeEnabled == true)
    #expect(restarted.isAutoHideEnabled == true)
    #expect(restarted.railScale == 0.70)
}

@Test
func miniModeOnlyCompactsAnIdleRailAndExpandsOnHover() {
    #expect(HUDLayout.railScale(miniMode: false, isHovered: false) == 1)
    #expect(HUDLayout.railScale(miniMode: true, isHovered: false) == 0.70)
    #expect(HUDLayout.railScale(miniMode: true, isHovered: true) == 1)
    #expect(
        HUDLayout.railScale(miniMode: true, isHovered: false) == 0.70,
        "an idle Mini rail remains compact when no interaction holds it open"
    )
}

@Test
func hiddenHUDRetractsCompletelyPastEachScreenEdge() {
    let normal = CGRect(x: 100, y: 200, width: 600, height: 900)
    let distance: CGFloat = 70

    #expect(HUDVisibilityGeometry.hiddenFrame(normal, edge: .right, retraction: distance).minX == normal.minX + distance)
    #expect(HUDVisibilityGeometry.hiddenFrame(normal, edge: .left, retraction: distance).minX == normal.minX - distance)
    #expect(HUDVisibilityGeometry.hiddenFrame(normal, edge: .top, retraction: distance).minY == normal.minY + distance)
    #expect(HUDVisibilityGeometry.hiddenFrame(normal, edge: .bottom, retraction: distance).minY == normal.minY - distance)
}

@MainActor
@Test
func openCardsKeepMiniExpandedWhenThePointerLeavesTheRail() {
    func scale(_ mode: HUDSurfaceState.Mode, hovered: Bool, fitScale: CGFloat = 1) -> CGFloat {
        HUDRootView(
            surface: .constant(HUDSurfaceState(mode: mode)),
            isExternallyHovered: .constant(hovered),
            edge: .right,
            isMiniModeEnabled: true,
            railFitScale: fitScale,
            onSelect: { _ in }, onSettings: {}, onEdgeChange: { _ in }, onDismiss: {}
        ).tabScale
    }

    for mode: HUDSurfaceState.Mode in [.settings, .detail(providerId: "claude")] {
        #expect(scale(mode, hovered: false) == scale(mode, hovered: true),
                "moving from the rail into an open card must not move its attachment point")
        #expect(scale(mode, hovered: false) == 1)
        #expect(scale(mode, hovered: false, fitScale: 0.8) == 0.8,
                "an open card must still respect the screen-fit limit")
    }
    #expect(scale(.idle, hovered: false) == 0.70)
    #expect(scale(.idle, hovered: true) == 1)
}

@Test
func edgeActivationZoneTracksTheConfiguredEdge() {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let thickness: CGFloat = 4

    #expect(HUDVisibilityGeometry.activationZone(in: screen, edge: .right, thickness: thickness).contains(CGPoint(x: 1439, y: 450)))
    #expect(!HUDVisibilityGeometry.activationZone(in: screen, edge: .right, thickness: thickness).contains(CGPoint(x: 100, y: 450)))
    #expect(HUDVisibilityGeometry.activationZone(in: screen, edge: .left, thickness: thickness).contains(CGPoint(x: 1, y: 450)))
    #expect(HUDVisibilityGeometry.activationZone(in: screen, edge: .top, thickness: thickness).contains(CGPoint(x: 720, y: 899)))
    #expect(HUDVisibilityGeometry.activationZone(in: screen, edge: .bottom, thickness: thickness).contains(CGPoint(x: 720, y: 1)))
}

@Test
func pointerMonitoringUsesTheUsableScreenFrame() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let source = try String(
        contentsOf: root.appendingPathComponent("Sources/NightCrawler/UI/FloatingHUDController.swift"),
        encoding: .utf8
    )

    #expect(source.contains("screenFrame: screen.visibleFrame"))
    #expect(source.contains("activationZone(in: screen.visibleFrame"))
}

@Test
func pointerAwayFromARevealedHUDRequestsRetraction() {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

    #expect(HUDVisibilityGeometry.shouldRetract(
        point: CGPoint(x: 720, y: 450),
        screenFrame: screen,
        edge: .right,
        revealedDepth: 430
    ))
    #expect(!HUDVisibilityGeometry.shouldRetract(
        point: CGPoint(x: 1380, y: 450),
        screenFrame: screen,
        edge: .right,
        revealedDepth: 430
    ))
}

@Test
func openingDetailCancelsAPendingHideEvenWhenTheRailIsAlreadyVisible() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let source = try String(
        contentsOf: root.appendingPathComponent("Sources/NightCrawler/UI/FloatingHUDController.swift"),
        encoding: .utf8
    )

    #expect(source.contains(
        "private func reveal(animated: Bool) {\n        cancelPendingHide()\n        guard !isRevealed else { return }"
    ))
}

@Test
func openingDetailPreservesTabHoverAcrossTheRootViewRebuild() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let controller = try String(
        contentsOf: root.appendingPathComponent("Sources/NightCrawler/UI/FloatingHUDController.swift"),
        encoding: .utf8
    )
    let view = try String(
        contentsOf: root.appendingPathComponent("Sources/NightCrawler/UI/HUDRootView.swift"),
        encoding: .utf8
    )

    #expect(controller.contains("isExternallyHovered: Binding("))
    #expect(view.contains("@Binding var isExternallyHovered: Bool"))
    #expect(view.contains("hoveringRail || hoveringSettings || isExternallyHovered"))
}

@MainActor
@Test
func fullSettingsContentFitsItsAllocatedCardHeight() {
    let suiteName = "NightCrawlerTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = UsageStore(defaults: defaults)
    store.setDemoMode(true)
    let content = SettingsView(
        edge: .right, isMiniModeEnabled: true, isAutoHideEnabled: false,
        onEdgeChange: { _ in }, onMiniModeChange: { _ in }, onAutoHideChange: { _ in }
    ).environmentObject(store)
        .frame(width: HUDLayout.cardWidth - 2 * HUDLayout.cardPadding)
    let host = NSHostingView(rootView: content)
    let required = host.fittingSize.height + 2 * HUDLayout.cardPadding
    let allocated = HUDLayout.settingsCardHeight(
        providerCount: store.providerCatalog.count,
        routingToolCount: store.routingToolStates.count
    )
    #expect(required <= allocated, "all settings including the last availability row must fit")
}

@Test
func settingsHoverIsBoundToTheButtonBeforePanelPositioning() throws {
    // Static modifier-order lock: SwiftUI's physical pointer tracking cannot be
    // driven by NSWindow.sendEvent in this unit harness. Verify the real app too.
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let source = try String(contentsOf: root.appendingPathComponent(
        "Sources/NightCrawler/UI/HUDRootView.swift"), encoding: .utf8)
    let start = try #require(source.range(of: "private func settingsHandle"))
    let end = try #require(source.range(of: "private var tabScaleAnchor"))
    let handle = source[start.lowerBound..<end.lowerBound]
    let hover = try #require(handle.range(of: ".onHover"))
    let position = try #require(handle.range(of: ".position"))
    #expect(hover.lowerBound < position.lowerBound,
            "hover must track the visible gear, not the panel-sized positioning wrapper")
}

@MainActor
@Test
func clickingSlideoutsKeepsTheNativeHoverTrackingViewAlive() throws {
    let app = NSApplication.shared
    let existingWindows = Set(app.windows.map(ObjectIdentifier.init))
    let suiteName = "NightCrawlerTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = UsageStore(providers: [], defaults: defaults)
    store.setDemoMode(true)
    let controller = FloatingHUDController(store: store, defaults: defaults)
    controller.show()
    defer { controller.hide() }
    controller.setMiniModeEnabled(true)
    let panel = try #require(app.windows.first { !existingWindows.contains(ObjectIdentifier($0)) })
    let hoverTrackingView = try #require(panel.contentView?.subviews.first)

    controller.showSettings()
    #expect(controller.surface.mode == .settings)
    #expect(panel.contentView?.subviews.first === hoverTrackingView,
            "opening a card must not detach the view and reset its mouse tracking")
    controller.showSettings()
    #expect(controller.surface.mode == .idle)
    #expect(panel.contentView?.subviews.first === hoverTrackingView)
}

@MainActor
@Test
func currentSessionOnlyAddsWarningOrCriticalGlyphColor() {
    func reading(sessionPercent: Double) -> UsageReading {
        UsageReading(
            providerId: "claude",
            label: "Claude Code",
            accountId: nil,
            authMode: "subscription",
            source: "test",
            windows: [
                UsageWindow(id: "session", label: "Current session", used: Int(sessionPercent), limit: 100, usedPercent: sessionPercent, windowMinutes: 300, resetsAt: nil),
                UsageWindow(id: "weekly_all", label: "All models", used: 20, limit: 100, usedPercent: 20, windowMinutes: 10_080, resetsAt: nil),
            ],
            status: .live,
            observedAt: Date(),
            error: nil
        )
    }

    #expect(ProviderIcon.sessionAlertBand(for: reading(sessionPercent: 49)) == nil)
    #expect(ProviderIcon.sessionAlertBand(for: reading(sessionPercent: 50)) == .watch)
    #expect(ProviderIcon.sessionAlertBand(for: reading(sessionPercent: 70)) == .critical)

    let codex = UsageReading(
        providerId: "codex",
        label: "Codex CLI",
        accountId: nil,
        authMode: "subscription",
        source: "test",
        windows: [
            UsageWindow(id: "primary", label: "Current session", used: 95, limit: 100, usedPercent: 95, windowMinutes: 300, resetsAt: nil),
            UsageWindow(id: "secondary", label: "Weekly", used: 10, limit: 100, usedPercent: 10, windowMinutes: 10_080, resetsAt: nil),
        ],
        status: .live,
        observedAt: Date(),
        error: nil
    )
    #expect(ProviderIcon.sessionAlertBand(for: codex) == .critical)
}
