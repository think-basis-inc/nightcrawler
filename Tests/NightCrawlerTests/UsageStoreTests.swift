import Combine
import Foundation
import Testing
@testable import NightCrawler

@MainActor
@Test
func claudeIsEnabledByDefaultOnAFreshInstall() {
    let suiteName = "NightCrawlerTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = UsageStore(providers: [], defaults: defaults)

    #expect(store.isProviderEnabled("claude"))
}

@MainActor
@Test
func savedProviderVisibilityGainsClaudeOnceThenRespectsLaterDisable() {
    let suiteName = "NightCrawlerTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.set(["codex", "cursor"], forKey: "enabledProviderIds")

    let first = UsageStore(providers: [], defaults: defaults)
    #expect(first.isProviderEnabled("claude"))

    first.toggle(providerId: "claude")
    #expect(!first.isProviderEnabled("claude"))

    let restarted = UsageStore(providers: [], defaults: defaults)
    #expect(!restarted.isProviderEnabled("claude"))
}

@MainActor
@Test
func storeFiltersDisabledProviders() async {
    let store = UsageStore(providers: [AlwaysAvailableProvider()])
    store.enabledProviderIds = []
    await store.refresh()
    #expect(store.readings.isEmpty)
}

@MainActor
@Test
func storeIncludesEnabledProvider() async {
    let store = UsageStore(providers: [AlwaysAvailableProvider()])
    store.enabledProviderIds = ["always"]
    await store.refresh()
    #expect(store.readings.count == 1)
}

@MainActor
@Test
func fastProviderReachesTheEndpointBeforeASlowProviderFinishes() async {
    let suiteName = "NightCrawlerTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = UsageStore(
        providers: [TimedProvider(id: "fast", delay: .milliseconds(5)), TimedProvider(id: "slow", delay: .milliseconds(400))],
        defaults: defaults
    )
    store.enabledProviderIds = ["fast", "slow"]

    let updates = store.$readings.values
    let refresh = Task { await store.refresh() }
    for await readings in updates {
        if readings.contains(where: { $0.providerId == "fast" }) {
            #expect(!readings.contains { $0.providerId == "slow" })
            break
        }
    }
    await refresh.value
}

@MainActor
@Test
func transientFailureKeepsTheLastGoodProviderReading() async throws {
    let suiteName = "NightCrawlerTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = UsageStore(providers: [FailingProvider()], defaults: defaults)
    store.enabledProviderIds = ["unstable"]
    let observedAt = Date().addingTimeInterval(-30)
    store.readings = [fixtureReading(id: "unstable", percent: 42, observedAt: observedAt)]

    await store.refresh()

    let reading = try #require(store.readings.first { $0.providerId == "unstable" })
    #expect(reading.status == .live)
    #expect(reading.windows.first?.usedPercent == 42)
    #expect(reading.observedAt == observedAt)
    #expect(reading.error?.contains("refresh") == true)
}

@MainActor
@Test
func successfulUnknownQuotaReplacesInventedLastGoodZero() async throws {
    let suiteName = "NightCrawlerTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let provider = MockProvider(id: "copilot", label: "GitHub Copilot")
    let store = UsageStore(providers: [provider], defaults: defaults)
    store.enabledProviderIds = ["copilot"]
    store.readings = [fixtureReading(id: "copilot", percent: 0, observedAt: Date().addingTimeInterval(-30))]
    provider.nextReading = UsageReading(
        providerId: "copilot",
        label: "GitHub Copilot",
        accountId: nil,
        authMode: "subscription",
        source: "copilot_account_quota",
        windows: [],
        status: .unknown,
        observedAt: nil,
        error: "Copilot did not report a finite subscription allowance"
    )

    await store.refresh()

    let reading = try #require(store.readings.first { $0.providerId == "copilot" })
    #expect(reading.status == .unknown)
    #expect(reading.windows.isEmpty)
    #expect(ProviderIcon.percentageText(for: reading) == nil)
    let resource = try #require(CapacitySnapshot.make(from: store).resources.first { $0.id == "copilot" })
    #expect(resource.capacity.windows.isEmpty)
    #expect(resource.capacity.status == .unknown)
}

@MainActor
@Test
func expiredLastGoodReadingDoesNotRemainLiveAfterARefreshFailure() async throws {
    let suiteName = "NightCrawlerTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = UsageStore(providers: [FailingProvider()], defaults: defaults)
    store.enabledProviderIds = ["unstable"]
    let observedAt = Date().addingTimeInterval(-600)
    store.readings = [fixtureReading(id: "unstable", percent: 42, observedAt: observedAt)]

    await store.refresh()

    let reading = try #require(store.readings.first { $0.providerId == "unstable" })
    #expect(reading.status == .needsAuth)
    #expect(reading.windows.first?.usedPercent == 42)
    #expect(reading.observedAt == observedAt)
    #expect(ProviderIcon.percentageText(for: reading) == nil)
    let resource = try #require(CapacitySnapshot.make(from: store).resources.first { $0.id == "unstable" })
    #expect(resource.available == .unavailable)
    #expect(resource.capacity.status == .unavailable)
    #expect(resource.capacity.freshness == .stale)
}

@MainActor
@Test
func cubicLastReportedAllowanceStaysLiveAfterAStaleRefreshFailure() async throws {
    let suiteName = "NightCrawlerTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let provider = MockProvider(id: "cubic", label: "Cubic")
    let store = UsageStore(providers: [provider], defaults: defaults)
    let observedAt = Date().addingTimeInterval(-3 * 24 * 60 * 60)
    store.readings = [
        UsageReading(
            providerId: "cubic",
            label: "Cubic",
            accountId: nil,
            authMode: "github",
            source: "cubic_github_check",
            windows: [
                UsageWindow(
                    id: "reviewed_lines",
                    label: "Last reported lines",
                    used: 302_778,
                    limit: 300_000,
                    usedPercent: 100.926,
                    windowMinutes: nil,
                    resetsAt: Date().addingTimeInterval(7 * 24 * 60 * 60),
                    observedAt: observedAt
                ),
            ],
            status: .live,
            observedAt: observedAt,
            error: "Last reported by Cubic; not a live balance"
        ),
    ]
    provider.nextReading = UsageReading(
        providerId: "cubic",
        label: "Cubic",
        accountId: nil,
        authMode: "unknown",
        source: "timeout",
        windows: [],
        status: .error("Usage refresh timed out"),
        observedAt: nil,
        error: "Usage refresh timed out"
    )

    await store.refresh(providerId: "cubic")

    let reading = try #require(store.readings.first { $0.providerId == "cubic" })
    #expect(reading.status == .live)
    #expect(reading.windows.first?.usedPercent == 100.926)
    #expect(reading.observedAt == observedAt)
    #expect(ProviderIcon.percentageText(for: reading) == "100.9%")
}

@MainActor
@Test
func enablingAProviderPutsItOnTheRailBeforeTheReadFinishes() throws {
    let suiteName = "NightCrawlerTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.set(true, forKey: "migratedDefaultEnabledClaude")
    defaults.set(true, forKey: "migratedDefaultEnabledGrokBot")
    defaults.set(["cursor"], forKey: "enabledProviderIds")
    let routingTools = RoutingToolState.defaults.map {
        RoutingToolState(id: $0.id, label: $0.label, enabled: false, available: $0.available)
    }
    defaults.set(try JSONEncoder().encode(routingTools), forKey: "routingToolStates")

    let store = UsageStore(
        providers: [HangingProvider(id: "cursor"), HangingProvider(id: "grokbot")],
        defaults: defaults
    )
    store.readings = [fixtureReading(id: "cursor", percent: 64, observedAt: Date())]

    #expect(store.orderedReadings.map(\.providerId) == ["cursor"])
    let before = HUDLayout.panelSize(cellCount: store.orderedReadings.count, edge: .right)

    store.toggle(providerId: "grokbot")

    #expect(store.orderedReadings.map(\.providerId) == ["cursor", "grokbot"])
    let after = HUDLayout.panelSize(cellCount: store.orderedReadings.count, edge: .right)
    #expect(after.height > before.height)
}

@MainActor
@Test
func hangingSiblingReadMustReleaseThePollLoopSoClaudeCanRefreshAgain() async throws {
    let suiteName = "NightCrawlerTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let claude = SequencePercentProvider(id: "claude", percents: [74, 76])
    let store = UsageStore(
        providers: [HangingProvider(id: "cursor"), claude],
        defaults: defaults,
        providerReadBudget: 0.25
    )
    store.enabledProviderIds = ["cursor", "claude"]

    let firstFinished = PollCompletion()
    let first = Task {
        await store.poll()
        firstFinished.done = true
    }
    // The hung Cursor read has a 0.25s budget; allow slack for a loaded test host.
    let firstDeadline = Date().addingTimeInterval(5)
    while !firstFinished.done, Date() < firstDeadline {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(firstFinished.done, "the poll loop must finish despite the hung Cursor read")
    #expect(store.readings.first { $0.providerId == "claude" }?.windows.first?.usedPercent == 74)

    await store.poll()
    first.cancel()

    let reading = try #require(store.readings.first { $0.providerId == "claude" })
    #expect(
        reading.windows.first?.usedPercent == 76,
        "a hung Cursor credential read must not freeze Claude at the last cache percent"
    )
}

@MainActor
@Test
func claudeOAuthSuccessMustNotWaitForAHungCLIAndMissThePollBudget() async throws {
    let suiteName = "NightCrawlerTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let oauthJSON = """
    {
        "five_hour": {
            "utilization": 19,
            "resets_at": "2026-09-10T22:00:00Z"
        },
        "seven_day": {
            "utilization": 61,
            "resets_at": "2026-09-11T19:00:00Z"
        }
    }
    """
    let httpResponse = HTTPURLResponse(
        url: URL(string: "https://api.anthropic.com/api/oauth/usage")!,
        statusCode: 200,
        httpVersion: "HTTP/1.1",
        headerFields: ["Content-Type": "application/json"]
    )!
    let credentials = ClaudeCredentialStore(
        fileURL: URL(fileURLWithPath: "/fixture/credentials.json"),
        reader: { _ in
            let payload: [String: Any] = [
                "claudeAiOauth": [
                    "accessToken": "test-subscription-token",
                    "expiresAt": (Date().timeIntervalSince1970 + 3600) * 1000,
                    "subscriptionType": "max",
                ]
            ]
            return try! JSONSerialization.data(withJSONObject: payload)
        }
    )
    let provider = ClaudeCodeUsageProvider(
        credentials: credentials,
        localUsage: ClaudeLocalUsageCache(
            fileURL: URL(fileURLWithPath: "/missing/claude.json"),
            reader: { _ in nil }
        ),
        sessionDataLoader: { _ in (Data(oauthJSON.utf8), httpResponse) },
        cliWindowsReader: {
            try? await Task.sleep(for: .seconds(60))
            return []
        }
    )
    let store = UsageStore(
        providers: [provider],
        defaults: defaults,
        claudeCredentials: credentials,
        providerReadBudget: 0.4
    )
    store.enabledProviderIds = ["claude"]

    await store.refresh()

    let reading = try #require(store.readings.first { $0.providerId == "claude" })
    #expect(reading.status == .live, "a hung Claude /usage spawn must not discard the live OAuth windows")
    #expect(reading.windows.contains { $0.id == "session" && $0.usedPercent == 19 })
    #expect(reading.windows.contains { $0.id == "weekly_all" && $0.usedPercent == 61 })
}

@MainActor
@Test
func overlappingPollsDoNotReadTheSameProviderConcurrently() async {
    let suiteName = "NightCrawlerTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let probe = PollConcurrencyProbe()
    let store = UsageStore(
        providers: [ConcurrencyProbeProvider(probe: probe)],
        defaults: defaults
    )
    store.enabledProviderIds = ["concurrency"]

    let first = Task { await store.poll() }
    try? await Task.sleep(for: .milliseconds(10))
    let second = Task { await store.poll() }
    await first.value
    await second.value

    #expect(await probe.maximum == 1)
}

@MainActor
@Test
func lastGoodProviderReadingsSurviveAppRestartAsStaleEndpointData() async throws {
    let suiteName = "NightCrawlerTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let provider = TimedProvider(id: "persisted", delay: .zero, percent: 37)
    let first = UsageStore(providers: [provider], defaults: defaults)
    first.enabledProviderIds = ["persisted"]
    await first.refresh()

    let restarted = UsageStore(providers: [provider], defaults: defaults)
    let reading = try #require(restarted.readings.first { $0.providerId == "persisted" })
    #expect(reading.status == .live)
    #expect(reading.windows.first?.usedPercent == 37)
    let snapshot = CapacitySnapshot.make(from: restarted, now: Date().addingTimeInterval(180))
    let capacity = try #require(snapshot.resources.first { $0.id == "persisted" })
    #expect(capacity.available == .unknown)
    #expect(capacity.capacity.freshness == .stale)
    #expect(capacity.capacity.windows.first?.usedPercent == 37)
}

struct AlwaysAvailableProvider: UsageProvider {
    let id = "always"
    let label = "Always"
    var isAvailable: Bool { true }

    func read() async -> UsageReading {
        UsageReading(
            providerId: id,
            label: label,
            accountId: nil,
            authMode: "test",
            source: "test",
            windows: [],
            status: .live,
            observedAt: Date(),
            error: nil
        )
    }
}

private struct TimedProvider: UsageProvider {
    let id: String
    let delay: Duration
    var percent: Double = 25
    var label: String { id.capitalized }
    var isAvailable: Bool { true }

    func read() async -> UsageReading {
        try? await Task.sleep(for: delay)
        return fixtureReading(id: id, percent: percent, observedAt: Date())
    }
}

@MainActor
private final class PollCompletion {
    var done = false
}

private struct HangingProvider: UsageProvider {
    let id: String
    var label: String { id.capitalized }
    var isAvailable: Bool { true }

    func read() async -> UsageReading {
        try? await Task.sleep(for: .seconds(60))
        return fixtureReading(id: id, percent: 0, observedAt: Date())
    }
}

private final class SequencePercentProvider: UsageProvider, @unchecked Sendable {
    let id: String
    let label: String
    private var percents: [Double]

    init(id: String, percents: [Double]) {
        self.id = id
        self.label = id.capitalized
        self.percents = percents
    }

    var isAvailable: Bool { true }

    func read() async -> UsageReading {
        let percent = percents.isEmpty ? 0 : percents.removeFirst()
        if percents.isEmpty { percents = [percent] }
        return fixtureReading(id: id, percent: percent, observedAt: Date())
    }
}

private struct FailingProvider: UsageProvider {
    let id = "unstable"
    let label = "Unstable"
    var isAvailable: Bool { true }

    func read() async -> UsageReading {
        UsageReading(
            providerId: id,
            label: label,
            accountId: nil,
            authMode: "unknown",
            source: "test",
            windows: [],
            status: .needsAuth,
            observedAt: nil,
            error: "latest refresh failed"
        )
    }
}

private actor PollConcurrencyProbe {
    private(set) var active = 0
    private(set) var maximum = 0

    func begin() {
        active += 1
        maximum = max(maximum, active)
    }

    func end() {
        active -= 1
    }
}

private struct ConcurrencyProbeProvider: UsageProvider {
    let probe: PollConcurrencyProbe
    let id = "concurrency"
    let label = "Concurrency"
    var isAvailable: Bool { true }

    func read() async -> UsageReading {
        await probe.begin()
        try? await Task.sleep(for: .milliseconds(100))
        await probe.end()
        return fixtureReading(id: id, percent: 1, observedAt: Date())
    }
}

private func fixtureReading(id: String, percent: Double, observedAt: Date) -> UsageReading {
    UsageReading(
        providerId: id,
        label: id.capitalized,
        accountId: nil,
        authMode: "subscription",
        source: "test",
        windows: [
            UsageWindow(
                id: "weekly",
                label: "Weekly",
                used: Int(percent * 100),
                limit: 10_000,
                usedPercent: percent,
                windowMinutes: 10_080,
                resetsAt: observedAt.addingTimeInterval(86_400)
            ),
        ],
        status: .live,
        observedAt: observedAt,
        error: nil
    )
}

private final class MockProvider: UsageProvider, @unchecked Sendable {
    let id: String
    let label: String
    var nextReading: UsageReading?

    init(id: String, label: String) {
        self.id = id
        self.label = label
    }

    var isAvailable: Bool { true }
    func read() async -> UsageReading {
        nextReading!
    }
}

@MainActor
@Test
func claudePartialRefreshMissingFablePreservesPriorFableWindow() async throws {
    let suiteName = "NightCrawlerTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let mockClaude = MockProvider(id: "claude", label: "Claude Code")
    let store = UsageStore(providers: [mockClaude], defaults: defaults)

    let priorObservedAt = Date().addingTimeInterval(-300)
    let initialReading = UsageReading(
        providerId: "claude",
        label: "Claude Code",
        accountId: "test-account",
        authMode: "subscription",
        source: "claude_cli_usage",
        windows: [
            UsageWindow(id: "session", label: "Current session", used: 400, limit: 10_000, usedPercent: 4, windowMinutes: 300, resetsAt: nil),
            UsageWindow(id: "weekly_all", label: "All models", used: 5500, limit: 10_000, usedPercent: 55, windowMinutes: 10_080, resetsAt: nil),
            UsageWindow(id: "fable", label: "Fable", used: 8700, limit: 10_000, usedPercent: 87, windowMinutes: 10_080, resetsAt: nil),
        ],
        status: .live,
        observedAt: priorObservedAt,
        error: nil
    )
    store.readings = [initialReading]

    let newObservedAt = Date()
    mockClaude.nextReading = UsageReading(
        providerId: "claude",
        label: "Claude Code",
        accountId: "test-account",
        authMode: "subscription",
        source: "claude_cli_usage",
        windows: [
            UsageWindow(id: "session", label: "Current session", used: 600, limit: 10_000, usedPercent: 6, windowMinutes: 300, resetsAt: nil),
            UsageWindow(id: "weekly_all", label: "All models", used: 5600, limit: 10_000, usedPercent: 56, windowMinutes: 10_080, resetsAt: nil),
        ],
        status: .live,
        observedAt: newObservedAt,
        error: nil
    )

    await store.refresh(providerId: "claude")

    let reading = try #require(store.readings.first { $0.providerId == "claude" })
    #expect(reading.status == .live)
    #expect(reading.windows.first { $0.id == "session" }?.usedPercent == 6)
    #expect(reading.windows.first { $0.id == "weekly_all" }?.usedPercent == 56)
    #expect(reading.windows.first { $0.id == "fable" }?.usedPercent == 87)
    #expect(reading.innerRingWindow?.label == "Fable")
    #expect(reading.observedAt == newObservedAt)
    #expect(reading.windows.first { $0.id == "session" }?.observedAt == newObservedAt)
    #expect(reading.windows.first { $0.id == "fable" }?.observedAt == priorObservedAt)

    let capacity = try #require(
        CapacitySnapshot.make(from: store, now: newObservedAt)
            .resources.first { $0.id == "claude" }
    )
    #expect(capacity.available == .available)
    #expect(capacity.capacity.freshness == .fresh)
    #expect(capacity.capacity.windows.first { $0.id == "session" }?.freshness == .fresh)
    #expect(capacity.capacity.windows.first { $0.id == "fable" }?.freshness == .stale)
}

@MainActor
@Test
func claudePartialRefreshMissingWeeklyKeepsPriorWeeklyAndDoesNotHeadlineSession() async throws {
    let suiteName = "NightCrawlerTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let mockClaude = MockProvider(id: "claude", label: "Claude Code")
    let store = UsageStore(providers: [mockClaude], defaults: defaults)

    let priorObservedAt = Date().addingTimeInterval(-300)
    store.readings = [
        UsageReading(
            providerId: "claude",
            label: "Claude Code",
            accountId: "test-account",
            authMode: "subscription",
            source: "claude_local_cache",
            windows: [
                UsageWindow(id: "session", label: "Current session", used: 400, limit: 10_000, usedPercent: 4, windowMinutes: 300, resetsAt: nil, observedAt: priorObservedAt),
                UsageWindow(id: "weekly_all", label: "All models", used: 8800, limit: 10_000, usedPercent: 88, windowMinutes: 10_080, resetsAt: Date().addingTimeInterval(3600), observedAt: priorObservedAt),
                UsageWindow(id: "fable", label: "Fable", used: 10_000, limit: 10_000, usedPercent: 100, windowMinutes: 10_080, resetsAt: Date().addingTimeInterval(3300), observedAt: priorObservedAt),
            ],
            status: .live,
            observedAt: priorObservedAt,
            error: nil
        )
    ]

    mockClaude.nextReading = UsageReading(
        providerId: "claude",
        label: "Claude Code",
        accountId: "test-account",
        authMode: "subscription",
        source: "claude_cli_usage",
        windows: [
            UsageWindow(id: "session", label: "Current session", used: 2500, limit: 10_000, usedPercent: 25, windowMinutes: 300, resetsAt: Date().addingTimeInterval(3600), observedAt: Date()),
        ],
        status: .live,
        observedAt: Date(),
        error: nil
    )

    await store.refresh(providerId: "claude")

    let reading = try #require(store.readings.first { $0.providerId == "claude" })
    #expect(try #require(reading.outerRingWindow).id == "weekly_all")
    #expect(try #require(reading.outerRingWindow).usedPercent == 88)
    #expect(try #require(reading.innerRingWindow).id == "fable")
    #expect(reading.windows.first { $0.id == "session" }?.usedPercent == 25)
    #expect(ProviderIcon.percentageText(for: reading) == "88.0%")
    #expect(ProviderIcon.percentageText(for: reading) != "25.0%")
}
