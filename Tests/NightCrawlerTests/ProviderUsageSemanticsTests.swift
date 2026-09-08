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

@Test
func codexLabelsWindowsByDurationInsteadOfAssumingThePrimarySlotIsASession() {
    #expect(CodexUsageLabels.label(windowSeconds: 18_000) == "Current session")
    #expect(CodexUsageLabels.label(windowSeconds: 604_800) == "Weekly limit")
    #expect(CodexUsageLabels.label(windowSeconds: 2_592_000) == "Monthly limit")
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

    let fractional = UsageWindow(
        id: "other_models",
        label: "Other Models",
        used: 30,
        limit: 10_000,
        usedPercent: 0.3,
        windowMinutes: nil,
        resetsAt: nil
    )
    #expect(ProviderIcon.percentageText(for: fractional) == "0.3%")
    #expect(ProviderIcon.accessibilityText(for: fractional) == "0.3% used")
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

@Test
func cursorModelsAndOtherModelsUseSeparateConcentricRings() throws {
    let reading = UsageReading(
        providerId: "cursor",
        label: "Cursor",
        accountId: nil,
        authMode: "subscription",
        source: "fixture",
        windows: [
            UsageWindow(id: "cursor_models", label: "Cursor Models", used: 39, limit: 100, usedPercent: 39, windowMinutes: nil, resetsAt: nil),
            UsageWindow(id: "other_models", label: "Other Models", used: 1, limit: 100, usedPercent: 1, windowMinutes: nil, resetsAt: nil),
        ],
        status: .live,
        observedAt: Date(),
        error: nil
    )

    #expect(try #require(reading.outerRingWindow).id == "cursor_models")
    #expect(try #require(reading.innerRingWindow).id == "other_models")
}

@Test
func cursorUsageSummaryPreservesBothModelBuckets() throws {
    let root: [String: Any] = [
        "billingCycleStart": "2026-09-01T00:00:00Z",
        "billingCycleEnd": "2026-10-01T00:00:00Z",
        "individualUsage": [
            "plan": [
                "autoPercentUsed": 39.285,
                "apiPercentUsed": 0.3,
                "totalPercentUsed": 33.716,
            ],
        ],
    ]

    let windows = try #require(CursorUsageProvider.windows(from: root))

    #expect(windows.map(\.id) == ["cursor_models", "other_models"])
    #expect(windows.map(\.label) == ["Cursor Models", "Other Models"])
    #expect(windows.map(\.usedPercent) == [39.285, 0.3])
    #expect(windows.allSatisfy { $0.windowMinutes == 43_200 })
}

@MainActor
@Test
func routingToolsUseTheirProviderMarks() {
    #expect(ProviderGlyph.from(providerId: "devin") == .devin)
    #expect(ProviderGlyph.from(providerId: "cubic") == .cubic)
    #expect(ProviderGlyph.from(providerId: "copilot") == .copilot)
    #expect(ProviderGlyph.devin.bundledResourceURL != nil)
    #expect(ProviderGlyph.cubic.bundledResourceURL != nil)
    #expect(ProviderGlyph.copilot.bundledResourceURL != nil)
}

@MainActor
@Test
func devinAndCubicAreUsageProvidersRatherThanEmptySyntheticRows() throws {
    let ids = UsageStore.defaultProviders().map(\.id)
    #expect(ids.contains("devin"))
    #expect(ids.contains("cubic"))

    let suiteName = "NightCrawlerTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let providers = [
        SemanticCatalogProvider(id: "devin", label: "Devin"),
        SemanticCatalogProvider(id: "cubic", label: "Cubic"),
    ]
    let store = UsageStore(providers: providers, defaults: defaults)
    store.toggleRoutingTool("cubic")
    store.readings = [
        semanticReading(id: "devin", usedPercent: 8),
        semanticReading(id: "cubic", usedPercent: 100.926),
    ]

    #expect(store.orderedReadings.map(\.providerId) == ["devin", "cubic"])
    #expect(store.orderedReadings.map { $0.outerRingWindow?.usedPercent } == [8, 100.926])
}

private struct SemanticCatalogProvider: UsageProvider {
    let id: String
    let label: String
    var isAvailable: Bool { true }

    func read() async -> UsageReading { semanticReading(id: id, usedPercent: 0) }
}

private func semanticReading(id: String, usedPercent: Double) -> UsageReading {
    UsageReading(
        providerId: id,
        label: id.capitalized,
        accountId: nil,
        authMode: "test",
        source: "test",
        windows: [
            UsageWindow(
                id: "quota",
                label: "Quota",
                used: Int(usedPercent),
                limit: 100,
                usedPercent: usedPercent,
                windowMinutes: nil,
                resetsAt: nil
            )
        ],
        status: .live,
        observedAt: Date(),
        error: nil
    )
}

@Test
func dinoQuotaCacheCarriesDevinAndCubicUsageIntoNativeReadings() throws {
    let devinData = Data(#"{"devin":{"provider":"devin","label":"Devin","auth_mode":"subscription","state":"live","observed_at":"2026-09-07T15:26:00Z","source":"devin_cli_user_status","windows":[{"id":"weekly","label":"Weekly quota","used_percent":8,"window_minutes":10080,"resets_at":1789286400}],"error":null}}"#.utf8)
    let cubicData = Data(#"{"cubic":{"provider":"cubic","label":"Cubic","auth_mode":"unknown","state":"stale","observed_at":"2026-09-07T02:39:03Z","source":"cubic_github_check","windows":[{"id":"reviewed_lines","label":"Monthly reviewed lines","used_percent":100.926,"used_count":302778,"limit_count":300000,"resets_on":"2026-09-17"}],"error":"Last reported by Cubic; not a live balance"}}"#.utf8)

    let devin = try #require(DinoUsageCache.reading(from: devinData, providerId: "devin", fallbackLabel: "Devin"))
    let cubic = try #require(DinoUsageCache.reading(from: cubicData, providerId: "cubic", fallbackLabel: "Cubic"))

    #expect(devin.status == .live)
    #expect(devin.windows.first?.usedPercent == 8)
    #expect(cubic.status == .live)
    #expect(cubic.windows.first?.used == 302_778)
    #expect(cubic.windows.first?.limit == 300_000)
    #expect(cubic.windows.first?.usedPercent == 100.926)
    #expect(cubic.windows.first?.resetsAt == ISO8601DateFormatter().date(from: "2026-09-17T00:00:00Z"))
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
