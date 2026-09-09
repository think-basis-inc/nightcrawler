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
func copilotBusinessCreditsUsedShowAsACountNotAPercentOrBlank() {
    let window = UsageWindow(
        id: "premium_interactions",
        label: "Credits used",
        used: 4909,
        limit: 0,
        usedPercent: 0,
        windowMinutes: nil,
        resetsAt: ISO8601DateFormatter().date(from: "2026-10-01T00:00:00Z")
    )
    let reading = UsageReading(
        providerId: "copilot",
        label: "GitHub Copilot",
        accountId: nil,
        authMode: "subscription",
        source: "copilot_internal_user",
        windows: [window],
        status: .live,
        observedAt: Date(),
        error: nil
    )

    #expect(ProviderIcon.percentageText(for: window) == "4909")
    #expect(ProviderIcon.percentageText(for: reading) == "4909")
    #expect(ProviderIcon.accessibilityText(for: window) == "4909 credits used")
    #expect(ProviderIcon.percentageText(for: window).contains("%") == false)
}

@MainActor
@Test
func copilotBusinessCreditsDoNotBecomeAZeroPercentCapacityWindow() throws {
    let suiteName = "NightCrawlerTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = UsageStore(
        providers: [SemanticCatalogProvider(id: "copilot", label: "GitHub Copilot")],
        defaults: defaults
    )
    store.enabledProviderIds = ["copilot"]
    store.readings = [
        UsageReading(
            providerId: "copilot",
            label: "GitHub Copilot",
            accountId: nil,
            authMode: "subscription",
            source: "copilot_internal_user",
            windows: [
                UsageWindow(
                    id: "premium_interactions",
                    label: "Credits used",
                    used: 4909,
                    limit: 0,
                    usedPercent: 0,
                    windowMinutes: nil,
                    resetsAt: nil
                )
            ],
            status: .live,
            observedAt: Date(),
            error: nil
        )
    ]

    let window = try #require(CapacitySnapshot.make(from: store).resources.first { $0.id == "copilot" }?.capacity.windows.first)
    #expect(window.used == 4909)
    #expect(window.limit == 0)
    #expect(window.usedPercent == nil)
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
func cursorIncludedAndApiUseSeparateConcentricRings() throws {
    let reading = UsageReading(
        providerId: "cursor",
        label: "Cursor",
        accountId: nil,
        authMode: "subscription",
        source: "fixture",
        windows: [
            UsageWindow(id: "included", label: "Included usage", used: 42, limit: 100, usedPercent: 42, windowMinutes: nil, resetsAt: nil),
            UsageWindow(id: "api", label: "API usage", used: 2, limit: 100, usedPercent: 2, windowMinutes: nil, resetsAt: nil),
        ],
        status: .live,
        observedAt: Date(),
        error: nil
    )

    #expect(try #require(reading.outerRingWindow).id == "included")
    #expect(try #require(reading.innerRingWindow).id == "api")
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

    #expect(windows.map(\.id) == ["included", "api"])
    #expect(windows.map(\.label) == ["Included usage", "API usage"])
    #expect(windows.map(\.usedPercent) == [33.716, 0.3])
    #expect(windows.allSatisfy { $0.windowMinutes == 43_200 })
}

@MainActor
@Test
func cursorHeadlineMatchesIncludedTotalNotAutoPoolOrSpentLimit() throws {
    // Live Ultra shape: dashboard copy is "You've used 42% of your included total usage"
    // while autoPercentUsed is 49% and used/limit is 40000/40000 (100%).
    let root: [String: Any] = [
        "billingCycleStart": "2026-08-11T23:36:44Z",
        "billingCycleEnd": "2026-09-11T23:36:44Z",
        "autoModelSelectedDisplayMessage": "You've used 42% of your included total usage",
        "namedModelSelectedDisplayMessage": "You've used 2% of your included API usage",
        "individualUsage": [
            "plan": [
                "enabled": true,
                "used": 40_000,
                "limit": 40_000,
                "remaining": 0,
                "breakdown": [
                    "included": 40_000,
                    "bonus": 108_312,
                    "total": 148_312,
                ],
                "autoPercentUsed": 49.13333333333333,
                "apiPercentUsed": 1.8239999999999998,
                "totalPercentUsed": 42.374857142857145,
            ],
        ],
    ]

    let windows = try #require(CursorUsageProvider.windows(from: root))
    let reading = UsageReading(
        providerId: "cursor",
        label: "Cursor",
        accountId: nil,
        authMode: "subscription",
        source: "cursor_editor_usage",
        windows: windows,
        status: .live,
        observedAt: Date(),
        error: nil
    )

    #expect(windows.map(\.id) == ["included", "api"])
    #expect(windows.map(\.label) == ["Included usage", "API usage"])
    #expect(windows.map(\.usedPercent) == [42.374857142857145, 1.8239999999999998])
    #expect(windows.contains { $0.usedPercent == 49.13333333333333 } == false)
    #expect(windows.contains { abs($0.usedPercent - 100) < 0.0001 } == false)
    #expect(try #require(reading.outerRingWindow).id == "included")
    #expect(try #require(reading.outerRingWindow).usedPercent == 42.374857142857145)
    #expect(try #require(reading.innerRingWindow).id == "api")
    #expect(ProviderIcon.percentageText(for: reading) == "42%")
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
        DevinUsageProvider.parse(Data(#"{"userStatus":{"planStatus":{"weeklyQuotaRemainingPercent":92}},"planInfo":{"billingStrategy":"BILLING_STRATEGY_QUOTA"}}"#.utf8)),
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
