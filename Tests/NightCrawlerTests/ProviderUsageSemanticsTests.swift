import Foundation
import Testing
@testable import NightCrawler

@Test
func grokTotalAndProductBreakdownAreAllReportedAsUsed() throws {
    let config: [String: Any] = [
        "creditUsagePercent": 65.0,
        "currentPeriod": [
            "type": "USAGE_PERIOD_TYPE_WEEKLY",
            "start": "2026-09-04T03:55:26Z",
            "end": "2026-09-11T03:55:26Z",
        ],
        "productUsage": [
            ["product": "GrokBuild", "usagePercent": 64.0],
            ["product": "GrokChat", "usagePercent": 1.0],
            ["product": "GrokVoice", "usagePercent": NSNull()],
        ],
    ]

    let windows = GrokUsageProvider.windows(from: config)

    #expect(windows.map(\.id) == ["credits", "GrokBuild", "GrokChat"])
    #expect(windows.map(\.label) == ["Weekly SuperGrok Heavy Limit", "Grok Build", "Grok Chat"])
    #expect(windows.map(\.usedPercent) == [65, 64, 1])
}

@Test
func antigravityRemainingFractionIsInvertedExactlyOnce() throws {
    let data = Data(#"{"response":{"groups":[{"displayName":"Gemini Models","buckets":[{"bucketId":"gemini-weekly","remainingFraction":0.96262,"resetTime":"2026-09-07T14:12:34Z"}]}]}}"#.utf8)

    let window = try #require(AntigravityUsageProvider.windows(from: data).first)

    #expect(window.id == "gemini-weekly")
    #expect(window.label == "Gemini Models")
    #expect(abs(window.usedPercent - 3.738) < 0.00001)
}

@Test
func antigravityUsedAndLimitShapeRemainsUsed() throws {
    let data = Data(#"{"quotaGroups":[{"displayName":"Gemini","buckets":[{"name":"daily","displayName":"Daily","used":250,"limit":1000}]}]}"#.utf8)

    let window = try #require(AntigravityUsageProvider.windows(from: data).first)

    #expect(window.usedPercent == 25)
}

@MainActor
@Test
func compactUsageTextNamesTheDirection() {
    let window = UsageWindow(
        id: "credits",
        label: "Weekly",
        used: 6500,
        limit: 10000,
        usedPercent: 65,
        windowMinutes: 10080,
        resetsAt: nil
    )

    #expect(ProviderIcon.percentageText(for: window) == "65%")
    #expect(ProviderIcon.accessibilityText(for: window) == "65% used")
}

@MainActor
@Test
func providersWithoutFiniteUsageDoNotRenderPlaceholderDashes() {
    let reading = UsageReading(
        providerId: "cubic",
        label: "Cubic",
        accountId: nil,
        authMode: "local",
        source: "routing_state",
        windows: [],
        status: .unknown,
        observedAt: nil,
        error: nil
    )

    #expect(ProviderIcon.percentageText(for: reading) == nil)
}

@MainActor
@Test
func routingToolsUseTheirProviderMarks() {
    #expect(ProviderGlyph.from(providerId: "devin") == .devin)
    #expect(ProviderGlyph.from(providerId: "cubic") == .cubic)
    #expect(ProviderGlyph.devin.bundledResourceURL != nil)
    #expect(ProviderGlyph.cubic.bundledResourceURL != nil)
}

@Test
func demoDataUsesConsumedPercentagesForTheReportedCorrections() throws {
    let codex = try #require(DemoData.readings.first { $0.providerId == "codex" })
    let grok = try #require(DemoData.readings.first { $0.providerId == "grok" })

    #expect(codex.headlineWindow?.usedPercent == 9)
    #expect(grok.headlineWindow?.usedPercent == 65)
    #expect(grok.windows.first { $0.id == "GrokBuild" }?.usedPercent == 64)
    #expect(grok.windows.first { $0.id == "GrokChat" }?.usedPercent == 1)
}

@Test
func demoModeNeverPersistsIntoTheNextLaunch() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let source = try String(
        contentsOf: root.appendingPathComponent("Sources/NightCrawler/AppDelegate.swift"),
        encoding: .utf8
    )

    #expect(!source.contains("@UserDefault(\"demoMode\""))
    #expect(!source.contains("UserDefaults.standard.object(forKey: key)"))
}
