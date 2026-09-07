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
