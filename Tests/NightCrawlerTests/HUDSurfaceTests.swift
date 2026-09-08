import Foundation
import Testing
@testable import NightCrawler

@Test
func settingsAndProviderSelectionShareOneSurface() {
    var surface = HUDSurfaceState()
    #expect(surface.usesSeparateWindow == false)
    surface.selectProvider("claude")
    #expect(surface.mode == .detail(providerId: "claude"))
    surface.toggleSettings()
    #expect(surface.mode == .settings)
    #expect(surface.selectedProviderId == nil)
    surface.selectProvider("codex")
    #expect(surface.mode == .detail(providerId: "codex"))
    surface.dismiss()
    #expect(surface.mode == .idle)
}

@Test
func selectedProviderSurvivesRefresh() {
    var surface = HUDSurfaceState()
    surface.selectProvider("claude")
    surface.preserveAcrossRefresh()
    #expect(surface.mode == .detail(providerId: "claude"))
}

@Test
func selectingTheSameProviderClosesTheSlideout() {
    var surface = HUDSurfaceState()
    surface.selectProvider("claude")
    surface.selectProvider("claude")
    #expect(surface.mode == .idle)
}

@Test
func attachedSettingsExposeEveryPersistedScreenEdge() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let settings = try String(
        contentsOf: root.appendingPathComponent("Sources/NightCrawler/UI/SettingsView.swift"),
        encoding: .utf8
    )
    let rootView = try String(
        contentsOf: root.appendingPathComponent("Sources/NightCrawler/UI/HUDRootView.swift"),
        encoding: .utf8
    )

    #expect(settings.contains("Screen edge"))
    #expect(settings.contains("ForEach(NotchEdge.allCases"))
    #expect(!settings.contains(".accessibilityLabel(\"Move HUD to (candidate.rawValue) edge\")"))
    #expect(rootView.contains("onEdgeChange"))
}

@Test
func slideoutUsesACurvedLiquidNeckInsteadOfATriangle() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let source = try String(
        contentsOf: root.appendingPathComponent("Sources/NightCrawler/UI/HUDRootView.swift"),
        encoding: .utf8
    )

    #expect(source.contains("LiquidNeck(direction: direction)"))
    #expect(!source.contains("TooltipTail(direction: direction)"))
}

@Test
func selectingSettingsAgainClosesTheSlideout() {
    var surface = HUDSurfaceState()
    surface.toggleSettings()
    #expect(surface.mode == .settings)
    surface.toggleSettings()
    #expect(surface.mode == .idle)
}

@Test
func providerCellsUseButtonsSoDetailClicksAreReliable() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let source = try String(
        contentsOf: root.appendingPathComponent("Sources/NightCrawler/UI/HUDRootView.swift"),
        encoding: .utf8
    )

    #expect(source.contains("Button(action: { onSelect(reading) })"))
    #expect(!source.contains(".onTapGesture { onSelect(reading) }"))
}

@Test
func hudSourceDoesNotOpenASecondWindow() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let controller = try String(contentsOf: root.appendingPathComponent("Sources/NightCrawler/UI/FloatingHUDController.swift"), encoding: .utf8)
    let settings = try String(contentsOf: root.appendingPathComponent("Sources/NightCrawler/UI/SettingsView.swift"), encoding: .utf8)
    let app = try String(contentsOf: root.appendingPathComponent("Sources/NightCrawler/NightCrawlerApp.swift"), encoding: .utf8)
    #expect(!controller.contains("settingsWindow"))
    #expect(!controller.contains("detailPanel"))
    #expect(!controller.contains("NightCrawler Settings"))
    #expect(!controller.contains("hudFrame"))
    #expect(!controller.contains("isMovableByWindowBackground = true"))
    #expect(!controller.contains("height: 400"))
    #expect(!settings.contains("Form {"))
    #expect(!settings.contains("Toggle("))
    #expect(!app.contains("Settings {"))
}

@Test
func copilotAndClaudeSourcesDropObsoleteAuthPaths() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let copilot = try String(contentsOf: root.appendingPathComponent("Sources/NightCrawler/Providers/GitHubCopilotUsageProvider.swift"), encoding: .utf8)
    let claude = try String(contentsOf: root.appendingPathComponent("Sources/NightCrawler/Providers/ClaudeCodeUsageProvider.swift"), encoding: .utf8)
    let readme = try String(contentsOf: root.appendingPathComponent("README.md"), encoding: .utf8)
    #expect(!copilot.contains("users/copilot/usage"))
    #expect(!copilot.contains("nightcrawler.github.copilot"))
    #expect(copilot.contains("account.getQuota") || FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources/NightCrawler/Providers/CopilotRPCClient.swift").path))
    #expect(!claude.contains("Keychain.readGenericPassword"))
    #expect(!readme.contains("nightcrawler.github.copilot"))
    #expect(!readme.contains("security add-generic-password"))
}
