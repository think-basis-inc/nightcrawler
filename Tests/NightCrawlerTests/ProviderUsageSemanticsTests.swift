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

    #expect(ProviderIcon.percentageText(for: window) == "65.0%")
    #expect(ProviderIcon.accessibilityText(for: window) == "65.0% used")

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
func copilotBusinessCreditsRingAgainstOneSeatIncludedAllowance() throws {
    let result = CopilotQuotaParser.parseInternalUser([
        "copilot_plan": "business",
        "token_based_billing": true,
        "quota_reset_date": "2026-10-01",
        "quota_snapshots": [
            "premium_interactions": [
                "credits_used": 4909,
                "entitlement": 0,
                "unlimited": true,
                "percent_remaining": 100,
                "remaining": 0,
                "token_based_billing": true,
            ],
        ],
    ] as [String: Any])
    let windows = GitHubCopilotUsageProvider.windows(from: result)
    let window = try #require(windows.first)
    let reading = UsageReading(
        providerId: "copilot",
        label: "GitHub Copilot",
        accountId: nil,
        authMode: "subscription",
        source: "copilot_internal_user",
        windows: windows,
        status: .live,
        observedAt: Date(),
        error: nil
    )

    #expect(window.used == 4909)
    #expect(window.limit == 1_900)
    #expect(abs(window.usedPercent - (4_909.0 / 1_900.0 * 100)) < 0.000001)
    #expect(window.fraction == 1)
    #expect(ProviderIcon.percentageText(for: window) == "258.4%")
    #expect(ProviderIcon.percentageText(for: reading) == "258.4%")
    #expect(ProviderIcon.accessibilityText(for: window) == "258.4% used")
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
                    label: "Included credits",
                    used: 4909,
                    limit: 1_900,
                    usedPercent: 4_909.0 / 1_900.0 * 100,
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
    #expect(window.limit == 1_900)
    #expect(window.usedPercent != nil)
    #expect(window.usedPercent != 0)
    #expect(abs((window.usedPercent ?? 0) - (4_909.0 / 1_900.0 * 100)) < 0.000001)
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
func cursorRingIsIncludedThenOther() throws {
    let reading = UsageReading(
        providerId: "cursor",
        label: "Cursor",
        accountId: nil,
        authMode: "subscription",
        source: "fixture",
        windows: [
            UsageWindow(id: "included", label: "Included models", used: 42, limit: 100, usedPercent: 42, windowMinutes: nil, resetsAt: nil),
            UsageWindow(id: "auto", label: "Cursor Models", used: 59, limit: 100, usedPercent: 59, windowMinutes: nil, resetsAt: nil),
            UsageWindow(id: "api", label: "Other Models", used: 13, limit: 100, usedPercent: 13, windowMinutes: nil, resetsAt: nil),
            UsageWindow(id: "weekly", label: "Weekly usage", used: 2240, limit: 10_000, usedPercent: 22.4, windowMinutes: 10_080, resetsAt: nil),
        ],
        status: .live,
        observedAt: Date(),
        error: nil
    )

    #expect(try #require(reading.outerRingWindow).id == "included")
    #expect(try #require(reading.outerRingWindow).usedPercent == 42)
    #expect(try #require(reading.innerRingWindow).id == "api")
    #expect(try #require(reading.innerRingWindow).usedPercent == 13)
    #expect(reading.thirdRingWindow == nil)
    #expect(reading.outerRingWindow?.id != "weekly")
    #expect(reading.outerRingWindow?.id != "auto")
    #expect(reading.innerRingWindow?.id != "included")
}

@Test
func cursorOuterPrefersIncludedOverAuto() throws {
    let withAuto = UsageReading(
        providerId: "cursor",
        label: "Cursor",
        accountId: nil,
        authMode: "subscription",
        source: "fixture",
        windows: [
            UsageWindow(id: "included", label: "Included models", used: 42, limit: 100, usedPercent: 42, windowMinutes: nil, resetsAt: nil),
            UsageWindow(id: "auto", label: "Cursor Models", used: 59, limit: 100, usedPercent: 59, windowMinutes: nil, resetsAt: nil),
            UsageWindow(id: "api", label: "Other Models", used: 13, limit: 100, usedPercent: 13, windowMinutes: nil, resetsAt: nil),
        ],
        status: .live,
        observedAt: Date(),
        error: nil
    )
    #expect(try #require(withAuto.outerRingWindow).id == "included")
    #expect(try #require(withAuto.outerRingWindow).usedPercent == 42)
    #expect(withAuto.outerRingWindow?.id != "auto")
    #expect(try #require(withAuto.innerRingWindow).id == "api")
    #expect(withAuto.thirdRingWindow == nil)
}



@MainActor
@Test
func cursorIconPercentageIsMonthlyIncludedNotGrokBotWeekly() throws {
    let now = Date()
    let monthReset = now.addingTimeInterval(28 * 86_400)
    let weekReset = now.addingTimeInterval(3 * 86_400)
    let reading = UsageReading(
        providerId: "cursor",
        label: "Cursor",
        accountId: nil,
        authMode: "subscription",
        source: "cursor_editor_usage",
        windows: [
            UsageWindow(
                id: "weekly",
                label: "Weekly usage",
                used: 5_100,
                limit: 10_000,
                usedPercent: 51,
                windowMinutes: 10_080,
                resetsAt: weekReset
            ),
            UsageWindow(
                id: "included",
                label: "Included models",
                used: 1_800,
                limit: 10_000,
                usedPercent: 18,
                windowMinutes: 40_320,
                resetsAt: monthReset
            ),
            UsageWindow(
                id: "api",
                label: "Other Models",
                used: 300,
                limit: 10_000,
                usedPercent: 3,
                windowMinutes: 40_320,
                resetsAt: monthReset
            ),
        ],
        status: .live,
        observedAt: now,
        error: nil
    )

    #expect(try #require(reading.outerRingWindow).id == "included")
    #expect(try #require(reading.outerRingWindow).usedPercent == 18)
    #expect(try #require(reading.innerRingWindow).id == "api")
    #expect(reading.thirdRingWindow == nil)
    let text = try #require(ProviderIcon.percentageText(for: reading, now: now))
    #expect(text == "18.0%")
    #expect(text != "51.0%")
    #expect(text != "51%")
    #expect(reading.outerRingWindow?.id != "weekly")
}

@Test
func cursorUsageSummaryPublishesIncludedAndOtherNotSpentOrGrokBotWeekly() throws {
    // Live Ultra trap: included copy is 42%, used/limit is 40000/40000 (100%),
    // Auto is 49.133%. Grok Bot weekly 22.4% must not headline Cursor.
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
    let sand: [String: Any] = [
        "currentPeriodStart": "2026-09-09T04:34:11.479Z",
        "nextResetTimestampUtc": "2026-09-16T04:34:11.479Z",
        "usagePercent": 22.4,
        "hasNonZeroIncludedLimit": true,
        "grokPlanLabel": "Grok Bot Plan",
    ]

    let windows = try #require(CursorUsageProvider.windows(from: root, sand: sand))
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
    #expect(windows.contains { $0.id == "weekly" } == false)
    #expect(windows.first { $0.id == "included" }?.usedPercent == 42.374857142857145)
    #expect(windows.first { $0.id == "included" }?.label == "Included models")
    #expect(windows.first { $0.id == "api" }?.usedPercent == 1.8239999999999998)
    #expect(windows.first { $0.id == "api" }?.label == "Other Models")
    #expect(windows.contains { $0.id == "auto" } == false)
    #expect(windows.contains { abs($0.usedPercent - 100) < 0.0001 } == false)
    #expect(try #require(reading.outerRingWindow).id == "included")
    #expect(try #require(reading.outerRingWindow).usedPercent == 42.374857142857145)
    #expect(try #require(reading.innerRingWindow).id == "api")
    #expect(reading.thirdRingWindow == nil)
}


@MainActor
@Test
func cursorLiveUsageShowsTenthsInsteadOfAStuckInteger() throws {
    let window = UsageWindow(
        id: "included",
        label: "Included models",
        used: 5_691,
        limit: 10_000,
        usedPercent: 56.914857142857144,
        windowMinutes: 10_080,
        resetsAt: nil
    )
    let reading = UsageReading(
        providerId: "cursor",
        label: "Cursor",
        accountId: nil,
        authMode: "subscription",
        source: "cursor_editor_usage",
        windows: [window],
        status: .live,
        observedAt: Date(),
        error: nil
    )

    #expect(ProviderIcon.percentageText(for: window) == "56.9%")
    let text = try #require(ProviderIcon.percentageText(for: reading))
    #expect(text == "56.9%")
    #expect(text.localizedCaseInsensitiveContains("left") == false)
    #expect(text != "43.1% left")
    #expect(text != "56%", "tenths must stay visible on the used percent")
}

@MainActor
@Test
func percentageTextRoundsToTheVendorDisplayInsteadOfTruncating() {
    let window = UsageWindow(
        id: "weekly_all",
        label: "All models",
        used: 4_795,
        limit: 10_000,
        usedPercent: 47.95457142857143,
        windowMinutes: 10_080,
        resetsAt: nil
    )
    let reading = UsageReading(
        providerId: "claude",
        label: "Claude Code",
        accountId: nil,
        authMode: "subscription",
        source: "fixture",
        windows: [window],
        status: .live,
        observedAt: Date(),
        error: nil
    )

    #expect(ProviderIcon.percentageText(for: window) == "48.0%")
    #expect(ProviderIcon.percentageText(for: reading) == "48.0%")
    #expect(ProviderIcon.percentageText(for: window) != "47%", "truncation hid the vendor 48% used / 52% left")
}

@MainActor
@Test
func hudHidesPercentageWhenLiveReadingIsOlderThanFreshnessInterval() {
    let observedAt = Date().addingTimeInterval(-10 * 60)
    let reading = UsageReading(
        providerId: "cursor",
        label: "Cursor",
        accountId: nil,
        authMode: "subscription",
        source: "cursor_editor_usage",
        windows: [
            UsageWindow(
                id: "included",
                label: "Included usage",
                used: 4_200,
                limit: 10_000,
                usedPercent: 42,
                windowMinutes: 43_200,
                resetsAt: nil,
                observedAt: observedAt
            ),
        ],
        status: .live,
        observedAt: observedAt,
        error: nil
    )

    #expect(ProviderIcon.percentageText(for: reading) == nil)
}

@MainActor
@Test
func claudeRailKeepsAllModelsUsageVisibleWhileWindowsHaveNotReset() throws {
    let now = Date()
    let observedAt = now.addingTimeInterval(-10 * 60)
    let reading = UsageReading(
        providerId: "claude",
        label: "Claude Code",
        accountId: nil,
        authMode: "subscription",
        source: "claude_local_cache",
        windows: [
            UsageWindow(id: "session", label: "Current session", used: 900, limit: 10_000, usedPercent: 9, windowMinutes: 300, resetsAt: now.addingTimeInterval(3 * 3600), observedAt: observedAt),
            UsageWindow(id: "weekly_all", label: "All models", used: 8800, limit: 10_000, usedPercent: 88, windowMinutes: 10_080, resetsAt: now.addingTimeInterval(3600), observedAt: observedAt),
            UsageWindow(id: "fable", label: "Fable", used: 10_000, limit: 10_000, usedPercent: 100, windowMinutes: 10_080, resetsAt: now.addingTimeInterval(3300), observedAt: observedAt),
        ],
        status: .live,
        observedAt: observedAt,
        error: nil
    )

    #expect(try #require(reading.outerRingWindow).id == "weekly_all")
    #expect(try #require(reading.innerRingWindow).id == "fable")
    #expect(reading.isFreshlyObserved(now: now))
    #expect(ProviderIcon.percentageText(for: reading, now: now) == "88.0%")
}

@MainActor
@Test
func claudePercentageStaysWeeklyAllEvenWhenSessionIsHigher() throws {
    let now = Date()
    let reading = UsageReading(
        providerId: "claude",
        label: "Claude Code",
        accountId: nil,
        authMode: "subscription",
        source: "claude_oauth_usage",
        windows: [
            UsageWindow(id: "session", label: "Current session", used: 8000, limit: 10_000, usedPercent: 80, windowMinutes: 300, resetsAt: now.addingTimeInterval(3600), observedAt: now),
            UsageWindow(id: "weekly_all", label: "All models", used: 1200, limit: 10_000, usedPercent: 12, windowMinutes: 10_080, resetsAt: now.addingTimeInterval(5 * 86400), observedAt: now),
            UsageWindow(id: "fable", label: "Fable", used: 4000, limit: 10_000, usedPercent: 40, windowMinutes: 10_080, resetsAt: now.addingTimeInterval(5 * 86400), observedAt: now),
        ],
        status: .live,
        observedAt: now,
        error: nil
    )

    #expect(try #require(reading.outerRingWindow).id == "weekly_all")
    #expect(try #require(reading.outerRingWindow).usedPercent == 12)
    #expect(try #require(reading.innerRingWindow).id == "fable")
    #expect(ProviderIcon.percentageText(for: reading, now: now) == "12.0%")
    #expect(ProviderIcon.percentageText(for: reading, now: now) != "80.0%")
}

@MainActor
@Test
func claudeRailDoesNotFlipToSessionWhenWeeklyIsMissingFromAPoll() throws {
    let now = Date()
    let reading = UsageReading(
        providerId: "claude",
        label: "Claude Code",
        accountId: nil,
        authMode: "subscription",
        source: "claude_cli_usage",
        windows: [
            UsageWindow(id: "session", label: "Current session", used: 2500, limit: 10_000, usedPercent: 25, windowMinutes: 300, resetsAt: now.addingTimeInterval(3600), observedAt: now),
        ],
        status: .live,
        observedAt: now,
        error: nil
    )

    #expect(reading.outerRingWindow?.id != "session")
    #expect(reading.headlineWindow?.id == "session")
    #expect(ProviderIcon.percentageText(for: reading, now: now) != "25.0%")
    #expect(ProviderIcon.percentageText(for: reading, now: now) == nil)
}

@MainActor
@Test
func hudShowsCubicLastReportedAllowanceWhenTheCheckIsOlderThanLiveFreshness() {
    let now = ProviderHelpers.parseISO8601("2026-09-10T20:48:00Z")!
    let reading = CubicUsageProvider.parse(
        [[
            "app": ["id": 1_082_092, "slug": "cubic-dev-ai"],
            "name": "cubic · AI code reviewer",
            "status": "completed",
            "completed_at": "2026-09-07T20:21:26Z",
            "output": [
                "summary": "cubic has reviewed 302,778 of the 300,000 allowed lines of code this month. Reviews resume on 17 September 2026 (in 10 days)."
            ],
        ]],
        repository: "owner/repo",
        now: now
    )

    #expect(reading.status == .live)
    #expect(reading.windows.first?.id == "reviewed_lines")
    #expect(now.timeIntervalSince(reading.observedAt ?? .distantPast) > CapacitySnapshot.liveFreshnessInterval)
    #expect(ProviderIcon.percentageText(for: reading, now: now) == "100.9%")
}

@MainActor
@Test
func routingToolsUseTheirProviderMarks() {
    #expect(ProviderGlyph.from(providerId: "devin") == .devin)
    #expect(ProviderGlyph.from(providerId: "cubic") == .cubic)
    #expect(ProviderGlyph.from(providerId: "copilot") == .copilot)
    #expect(ProviderGlyph.from(providerId: "grokbot") == .grokbot)
    #expect(ProviderGlyph.from(providerId: "grokbot") != .grok)
    #expect(ProviderGlyph.devin.bundledResourceURL != nil)
    #expect(ProviderGlyph.cubic.bundledResourceURL != nil)
    #expect(ProviderGlyph.copilot.bundledResourceURL != nil)
    #expect(ProviderGlyph.grokbot.bundledResourceURL != nil)
}

@MainActor
@Test
func devinAndCubicAreUsageProvidersRatherThanEmptySyntheticRows() throws {
    let ids = UsageStore.defaultProviders().map(\.id)
    #expect(ids.contains("devin"))
    #expect(ids.contains("cubic"))
    #expect(ids.contains("grokbot"))
    #expect(try #require(UsageStore.defaultProviders().first { $0.id == "grokbot" }).label == "Grok Bot")

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
