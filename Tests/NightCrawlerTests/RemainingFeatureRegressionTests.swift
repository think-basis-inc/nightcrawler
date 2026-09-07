import Foundation
import Testing
@testable import NightCrawler

@MainActor
@Test
func settingsSurfaceIsSizedForTheWholeCatalog() {
    let providerCount = UsageStore.defaultProviders().count
    let requiredHeight = HUDLayout.settingsCardHeight(
        providerCount: providerCount,
        routingToolCount: RoutingToolState.defaults.count
    )
    #expect(HUDLayout.defaultMaxCardHeight >= requiredHeight)
}

@MainActor
@Test
func providerOrderAndRoutingStatePersistAcrossRestart() {
    let suiteName = "NightCrawlerTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let providers = [
        CatalogProvider(id: "alpha", label: "Alpha"),
        CatalogProvider(id: "beta", label: "Beta"),
        CatalogProvider(id: "gamma", label: "Gamma"),
    ]

    let first = UsageStore(providers: providers, defaults: defaults)
    first.moveProvider("gamma", by: -2)
    first.toggleRoutingTool("cubic")
    first.toggleRoutingToolAvailability("cubic")

    let restarted = UsageStore(providers: providers, defaults: defaults)
    #expect(restarted.providerOrder == ["gamma", "alpha", "beta"])
    #expect(restarted.routingToolStates.first?.enabled == true)
    #expect(restarted.routingToolStates.first?.available == true)
}

@MainActor
@Test
func corruptedSavedOrderIsDeduplicatedAndStaleIdsAreDropped() {
    let suiteName = "NightCrawlerTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.set(["beta", "beta", "removed"], forKey: "providerOrder")
    let providers = [
        CatalogProvider(id: "alpha", label: "Alpha"),
        CatalogProvider(id: "beta", label: "Beta"),
    ]

    let store = UsageStore(providers: providers, defaults: defaults)
    #expect(store.providerOrder == ["beta", "alpha"])
}

@MainActor
@Test
func orderedReadingsRespectVisibilityInDemoMode() {
    let suiteName = "NightCrawlerTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let providers = [
        CatalogProvider(id: "alpha", label: "Alpha"),
        CatalogProvider(id: "beta", label: "Beta"),
    ]
    let store = UsageStore(providers: providers, defaults: defaults)
    store.toggleRoutingTool("devin")
    store.enabledProviderIds = ["beta"]
    store.readings = [testReading(id: "alpha"), testReading(id: "beta")]

    #expect(store.orderedReadings.map(\.providerId) == ["beta"])
}

@MainActor
@Test
func cubicDefaultsToDisabledAndUnavailable() {
    let suiteName = "NightCrawlerTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = UsageStore(providers: [], defaults: defaults)
    let cubic = store.routingToolStates.first { $0.id == "cubic" }
    #expect(cubic?.enabled == false)
    #expect(cubic?.available == false)
}

@MainActor
@Test
func agentRoutingCatalogIncludesDevinAndCubic() {
    let suiteName = "NightCrawlerTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = UsageStore(providers: [], defaults: defaults)
    #expect(store.routingToolStates.map(\.id) == ["devin", "cubic"])
}

@MainActor
@Test
func enabledRoutingToolsAppearOnTheRailImmediately() {
    let suiteName = "NightCrawlerTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = UsageStore(providers: [], defaults: defaults)

    #expect(store.orderedReadings.map(\.providerId) == ["devin"])
    store.toggleRoutingTool("cubic")
    #expect(store.orderedReadings.map(\.providerId) == ["devin", "cubic"])
    #expect(store.orderedReadings.last?.status.isError == true)
    store.toggleRoutingTool("cubic")
    #expect(store.orderedReadings.map(\.providerId) == ["devin"])
}

@MainActor
@Test
func providerVisibilityChangesPersistAndFilterTheRail() {
    let suiteName = "NightCrawlerTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let providers = [
        CatalogProvider(id: "copilot", label: "GitHub Copilot"),
        CatalogProvider(id: "antigravity", label: "Antigravity"),
    ]
    let store = UsageStore(providers: providers, defaults: defaults)
    store.toggleRoutingTool("devin")
    store.enabledProviderIds = ["antigravity"]
    store.readings = [testReading(id: "copilot"), testReading(id: "antigravity")]

    store.toggle(providerId: "antigravity")
    store.toggle(providerId: "copilot")

    #expect(store.orderedReadings.map(\.providerId) == ["copilot"])
    let restarted = UsageStore(providers: providers, defaults: defaults)
    #expect(restarted.enabledProviderIds == ["copilot"])
}

@Test
func loopbackCapacityEndpointExistsAndIsPinnedToLoopback() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let endpoint = root.appendingPathComponent("Sources/NightCrawler/Routing/LocalCapacityServer.swift")
    #expect(FileManager.default.fileExists(atPath: endpoint.path))

    if FileManager.default.fileExists(atPath: endpoint.path) {
        let source = try String(contentsOf: endpoint, encoding: .utf8)
        #expect(source.contains("127.0.0.1"))
        #expect(source.contains("/v1/capacity"))
        #expect(!source.contains("0.0.0.0"))
    }
}

@MainActor
@Test
func capacitySnapshotSeparatesEnabledAvailableAndCapacityWithoutCredentials() throws {
    let suiteName = "NightCrawlerTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = UsageStore(
        providers: [CatalogProvider(id: "cursor", label: "Cursor")],
        defaults: defaults
    )
    store.enabledProviderIds = ["cursor"]
    store.readings = [
        UsageReading(
            providerId: "cursor",
            label: "Cursor",
            accountId: "must-not-escape",
            authMode: "secret-auth-mode",
            source: "cursor_usage",
            windows: [
                UsageWindow(
                    id: "monthly",
                    label: "Monthly",
                    used: 25,
                    limit: 100,
                    usedPercent: 25,
                    windowMinutes: nil,
                    resetsAt: nil
                ),
            ],
            status: .live,
            observedAt: Date(),
            error: nil
        ),
    ]

    let snapshot = CapacitySnapshot.make(from: store)
    let cursor = snapshot.resources.first { $0.id == "cursor" }
    let cubic = snapshot.resources.first { $0.id == "cubic" }
    #expect(cursor?.enabled == true)
    #expect(cursor?.available == .available)
    #expect(cursor?.capacity.status == .live)
    #expect(cursor?.capacity.windows.first?.usedPercent == 25)
    #expect(cubic?.enabled == false)
    #expect(cubic?.available == .unavailable)
    #expect(cubic?.capacity.status == .unknown)

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let json = String(decoding: try encoder.encode(snapshot), as: UTF8.self)
    #expect(!json.contains("must-not-escape"))
    #expect(!json.contains("secret-auth-mode"))
    #expect(!json.contains("accountId"))
}

@MainActor
@Test
func capacityHTTPIsReadOnlyAndServesTheVersionedRoute() {
    let snapshot = CapacitySnapshot(schemaVersion: 1, generatedAt: Date(), resources: [])
    let get = LocalCapacityHTTP.response(
        for: Data("GET /v1/capacity HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n".utf8),
        snapshot: snapshot
    )
    let post = LocalCapacityHTTP.response(
        for: Data("POST /v1/capacity HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n".utf8),
        snapshot: snapshot
    )

    #expect(String(decoding: get, as: UTF8.self).hasPrefix("HTTP/1.1 200 OK"))
    #expect(String(decoding: get, as: UTF8.self).contains("\"schemaVersion\":1"))
    #expect(String(decoding: post, as: UTF8.self).hasPrefix("HTTP/1.1 405 Method Not Allowed"))
}

@MainActor
@Test
func localCapacityListenerAcceptsItsLoopbackConfiguration() {
    let server = LocalCapacityServer {
        CapacitySnapshot(schemaVersion: 1, generatedAt: Date(), resources: [])
    }
    defer { server.stop() }

    #expect(throws: Never.self) {
        try server.start()
    }
}

@Test
func demoModeDoesNotStartTheCredentialPollingTimer() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let source = try String(
        contentsOf: root.appendingPathComponent("Sources/NightCrawler/AppDelegate.swift"),
        encoding: .utf8
    )

    #expect(!source.contains("store.startPolling(skipInitialPoll: isDemo)"))
    #expect(source.contains("store.setDemoMode(true)"))
}

@Test
func settingsOrbUsesItsWholeCircleAsAButton() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let source = try String(
        contentsOf: root.appendingPathComponent("Sources/NightCrawler/UI/HUDRootView.swift"),
        encoding: .utf8
    )

    #expect(source.contains("Button(action: onSettings)"))
    #expect(source.contains(".contentShape(Circle())"))
}

@MainActor
@Test
func demoModeProviderToggleDoesNotReadTheLiveAdapter() async throws {
    let suiteName = "NightCrawlerTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let counter = ProviderReadCounter()
    let store = UsageStore(
        providers: [CountingCatalogProvider(id: "copilot", label: "GitHub Copilot", counter: counter)],
        defaults: defaults
    )
    store.enabledProviderIds = ["copilot"]
    let demo = testReading(id: "copilot", source: "demo")
    store.setDemoMode(true, readings: [demo])

    store.toggle(providerId: "copilot")
    store.toggle(providerId: "copilot")
    try await Task.sleep(for: .milliseconds(50))

    #expect(await counter.value == 0)
    #expect(store.orderedReadings.first?.source == "demo")
}

private struct CatalogProvider: UsageProvider {
    let id: String
    let label: String
    var isAvailable: Bool { true }

    func read() async -> UsageReading {
        UsageReading(
            providerId: id,
            label: label,
            accountId: nil,
            authMode: "test",
            source: "test",
            windows: [],
            status: .unknown,
            observedAt: nil,
            error: nil
        )
    }
}

private actor ProviderReadCounter {
    var value = 0
    func increment() { value += 1 }
}

private struct CountingCatalogProvider: UsageProvider {
    let id: String
    let label: String
    let counter: ProviderReadCounter
    var isAvailable: Bool { true }

    func read() async -> UsageReading {
        await counter.increment()
        return testReading(id: id, source: "live")
    }
}

private func testReading(id: String, source: String = "test") -> UsageReading {
    UsageReading(
        providerId: id,
        label: id.capitalized,
        accountId: nil,
        authMode: "test",
        source: source,
        windows: [],
        status: .unknown,
        observedAt: nil,
        error: nil
    )
}
