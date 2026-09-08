import Foundation
import Testing
@testable import NightCrawler

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

    let refresh = Task { await store.refresh() }
    try? await Task.sleep(for: .milliseconds(80))

    #expect(store.readings.contains { $0.providerId == "fast" })
    #expect(!store.readings.contains { $0.providerId == "slow" })
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
