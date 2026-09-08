import Foundation
import Testing
@testable import NightCrawler

@Test
func usageBandUsesCodenotchThresholds() {
    #expect(UsageBand.band(for: 0.0) == .ample)
    #expect(UsageBand.band(for: 0.4999) == .ample)
    #expect(UsageBand.band(for: 0.50) == .watch)
    #expect(UsageBand.band(for: 0.6999) == .watch)
    #expect(UsageBand.band(for: 0.70) == .critical)
    #expect(UsageBand.band(for: 0.9999) == .critical)
    #expect(UsageBand.band(for: 1.0) == .exhausted)
    #expect(UsageBand.band(for: 1.4) == .exhausted)
}

@Test
func inverseFlaredRailIncludesBezelCorners() {
    let rect = CGRect(x: 0, y: 0, width: 70, height: 400)
    let path = SideNotchShape(edge: .right).path(in: rect)
    #expect(
        path.contains(CGPoint(x: rect.maxX - 1, y: rect.midY)),
        "rail body must weld to the bezel along the edge"
    )
    #expect(
        !path.contains(CGPoint(x: rect.midX, y: rect.minY + 5)),
        "inverse curl cuts the end cap; a capsule would fill that corner"
    )
    #expect(
        !path.contains(CGPoint(x: rect.minX + 0.5, y: rect.minY + 0.5)),
        "far-side top corner is cut by the inverse curl"
    )
}

@Test
func slideoutTailHasNoGapFromTheRail() {
    #expect(HUDLayout.tailGap == 0)
}

@Test
func slideoutUsesAOneSidedTeardropConnector() {
    let rect = CGRect(x: 0, y: 0, width: 60, height: 72)
    let path = LiquidNeck(direction: .leading).path(in: rect)

    #expect(path.contains(CGPoint(x: 1, y: rect.midY - 20)))
    #expect(path.contains(CGPoint(x: 1, y: rect.midY + 20)))
    #expect(path.contains(CGPoint(x: 59, y: rect.midY)))
    #expect(!path.contains(CGPoint(x: 59, y: rect.midY - 10)))
    #expect(
        !path.contains(CGPoint(x: rect.midX, y: rect.midY - 15)),
        "the teardrop sides must pull inward, not bulge into a convex leaf"
    )
    #expect(path.contains(CGPoint(x: rect.midX, y: rect.midY - 2)))
}

@Test
func liquidNeckUsesMostOfTheDetailCardEdgeInsteadOfCollapsingIntoABowTie() {
    let detailHeight = HUDLayout.cardHeight(windowCount: 3)
    #expect(HUDLayout.tailHeight >= detailHeight * 0.65)
}

@Test
func oneWindowSlideoutClampsTheConnectorRootToTheCard() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let source = try String(
        contentsOf: root.appendingPathComponent("Sources/NightCrawler/UI/HUDRootView.swift"),
        encoding: .utf8
    )

    #expect(
        source.contains("LiquidNeck.size(for: direction, cardAlong: cardAlong)"),
        "short detail cards must clamp the connector root instead of letting it overrun the rounded card"
    )
}

@Test
func liquidNeckSizeNeverExceedsItsCardEdge() {
    let shortCard = HUDLayout.cardHeight(windowCount: 1)
    let side = LiquidNeck.size(for: .leading, cardAlong: shortCard)
    let top = LiquidNeck.size(for: .down, cardAlong: HUDLayout.cardWidth)

    #expect(side.height <= shortCard - 2 * HUDLayout.cardCorner)
    #expect(top.width == HUDLayout.tailHeight)
}

@Test
func railLengthGrowsWithVisibleProviderCount() {
    let one = HUDLayout.bodyLength(cellCount: 1, edge: .right)
    let three = HUDLayout.bodyLength(cellCount: 3, edge: .right)
    let empty = HUDLayout.bodyLength(cellCount: 0, edge: .right)
    #expect(three > one)
    #expect(one > empty)
    let pitch = HUDLayout.cellPitch(for: .right)
    #expect(abs((three - one) - pitch * 2) < 0.001)
}

@Test
func railAutomaticallyFitsAllProvidersInsideTheVisibleScreenLength() {
    let available: CGFloat = 1_037
    let required = HUDLayout.requiredRailLength(cellCount: 11, edge: .right)
    let fit = HUDLayout.railFitScale(cellCount: 11, edge: .right, availableLength: available)

    #expect(fit < 1)
    #expect(required * fit <= available + 0.001)
    #expect(HUDLayout.railScale(miniMode: false, isHovered: false, fitScale: fit) == fit)
    #expect(HUDLayout.railScale(miniMode: true, isHovered: false, fitScale: fit) == HUDLayout.compactRailScale)
}

@Test
func slideoutAttachesInwardOnEveryEdge() {
    let panel = CGSize(width: 500, height: 900)
    let cardAlong: CGFloat = 226
    let slack = HUDLayout.slack(for: .right)
    let rail = HUDLayout.bodyDepth(for: .right)
    let tail = HUDLayout.tailLength
    let ring = slack + 120

    let right = HUDLayout.attachedSlideoutCenter(
        edge: .right, panelSize: panel, ringCenterAlong: ring,
        cardAlong: cardAlong, tailLength: tail, railDepth: rail, slack: slack
    )
    let left = HUDLayout.attachedSlideoutCenter(
        edge: .left, panelSize: panel, ringCenterAlong: ring,
        cardAlong: cardAlong, tailLength: tail, railDepth: rail, slack: slack
    )
    let top = HUDLayout.attachedSlideoutCenter(
        edge: .top, panelSize: panel, ringCenterAlong: ring,
        cardAlong: cardAlong, tailLength: tail, railDepth: rail, slack: slack
    )
    let bottom = HUDLayout.attachedSlideoutCenter(
        edge: .bottom, panelSize: panel, ringCenterAlong: ring,
        cardAlong: cardAlong, tailLength: tail, railDepth: rail, slack: slack
    )

    #expect(right.x < panel.width - rail, "right-edge card sits inward, left of the rail")
    #expect(left.x > rail, "left-edge card sits inward, right of the rail")
    #expect(top.y > rail, "top-edge card sits inward, below the rail")
    #expect(bottom.y < panel.height - rail, "bottom-edge card sits inward, above the rail")

    let attachedLength = cardAlong + tail
    #expect(abs((right.x + attachedLength / 2) - (panel.width - rail)) < 0.001)
    #expect(abs((left.x - attachedLength / 2) - rail) < 0.001)
    #expect(abs((top.y - attachedLength / 2) - rail) < 0.001)
    #expect(abs((bottom.y + attachedLength / 2) - (panel.height - rail)) < 0.001)
}

@Test
func claudeRailExposesConcentricAllModelsAndFableWindows() {
    let claude = DemoData.readings.first { $0.providerId == "claude" }
    #expect(claude?.outerRingWindow?.id == "weekly_all")
    #expect(claude?.outerRingWindow?.label == "All models")
    #expect(claude?.innerRingWindow?.id == "weekly_scoped")
    #expect(claude?.innerRingWindow?.label == "Fable")
    #expect((claude?.innerRingWindow?.usedPercent ?? 0) > (claude?.outerRingWindow?.usedPercent ?? 100))
    let codex = DemoData.readings.first { $0.providerId == "codex" }
    #expect(codex?.innerRingWindow == nil)
}

@Test
func scopedWeeklyWindowUsesFableLabel() {
    #expect(ClaudeUsageLabels.label(for: "weekly_scoped") == "Fable")
    #expect(ClaudeUsageLabels.label(for: "weekly_all") == "All models")
}

@Test
func fullSettingsCardFitsInsideScreenVisibleFrame() {
    struct InstalledScreen: ScreenDescribing {
        var frameValue: CGRect
        var visibleFrameValue: CGRect
    }
    let screen = InstalledScreen(
        frameValue: CGRect(x: 0, y: 0, width: 1728, height: 1117),
        visibleFrameValue: CGRect(x: 0, y: 47, width: 1728, height: 1037)
    )

    let cardRect = NotchGeometry.settingsCardScreenRect(
        for: screen,
        cellCount: 7,
        edge: .right,
        providerCount: 11,
        routingToolCount: 2,
        displayRowCount: 2
    )

    #expect(cardRect.minY >= screen.visibleFrameValue.minY, "bottom of settings card must not be clipped by the visible frame")
    #expect(screen.visibleFrameValue.contains(cardRect), "visibleFrame must contain the entire settings card")
}

@Test
func settingsRowsUseCompactMeasuredGeometrySoLowerProvidersRemainVisible() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let source = try String(
        contentsOf: root.appendingPathComponent("Sources/NightCrawler/UI/SettingsView.swift"),
        encoding: .utf8
    )

    #expect(source.contains(".frame(height: HUDLayout.settingsRowHeight)"))
    #expect(source.contains("HUDLayout.settingsRowSpacing"))
}
