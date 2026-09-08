import Foundation
import Testing
@testable import NightCrawler

@MainActor
@Test
func quotaProvidersDoNotDependOnAnotherMonitoringApp() throws {
    let providers = UsageStore.defaultProviders()
    for id in ["devin", "cubic"] {
        let provider = try #require(providers.first { $0.id == id })
        #expect(!String(describing: type(of: provider)).contains("Dino"),
                "\(id) must collect its own provider data, not another app's snapshots")
    }
}

private let devinFixture = Data(#"{"userStatus":{"planStatus":{"dailyQuotaRemainingPercent":94,"weeklyQuotaRemainingPercent":92,"weeklyQuotaResetAtUnix":"1789286400"}},"planInfo":{"billingStrategy":"BILLING_STRATEGY_QUOTA"}}"#.utf8)
private let reportDate = ProviderHelpers.parseISO8601("2026-09-07T20:21:26Z")!
private let sampleNow = ProviderHelpers.parseISO8601("2026-09-08T01:00:00Z")!
private func cubicCheck(summary: String = "cubic has reviewed 302,778 of the 300,000 allowed lines of code this month. Reviews resume on 17 September 2026 (in 10 days).") -> [String: Any] {
    ["app": ["id": 1_082_092, "slug": "cubic-dev-ai"], "name": "cubic · AI code reviewer",
     "status": "completed", "completed_at": "2026-09-07T20:21:26Z", "output": ["summary": summary]]
}

@Test
func directDevinQuotasConvertRemainingToUsedAndDoNotInventMissingPools() {
    let reading = DevinUsageProvider.parse(devinFixture, now: sampleNow)
    #expect(reading.windows.map(\.usedPercent) == [6, 8])
    #expect(reading.source == "devin_user_status")
    #expect(reading.observedAt == sampleNow)
    for invalid in ["true", "-1", "101", "null", "\"NaN\""] {
        let data = Data("{\"userStatus\":{\"planStatus\":{\"weeklyQuotaRemainingPercent\":\(invalid)}},\"planInfo\":{\"billingStrategy\":\"BILLING_STRATEGY_QUOTA\"}}".utf8)
        #expect(DevinUsageProvider.parse(data).windows.isEmpty)
    }
    let weeklyOnly = Data(#"{"userStatus":{"planStatus":{"weeklyQuotaRemainingPercent":0}},"planInfo":{"billingStrategy":"BILLING_STRATEGY_QUOTA"}}"#.utf8)
    #expect(DevinUsageProvider.parse(weeklyOnly).windows.map(\.usedPercent) == [100])
}

@Test
func devinCredentialsFailClosedOnWrongOriginsDuplicatesAndOversizedInput() {
    let valid = "api_server_url = \"https://server.codeium.com\"\nwindsurf_api_key = \"test-credential\"\n"
    #expect(DevinUsageProvider.credential(from: Data(valid.utf8)) == "test-credential")
    #expect(DevinUsageProvider.credential(from: Data(valid.replacingOccurrences(of: "server.codeium.com", with: "example.com").utf8)) == nil)
    #expect(DevinUsageProvider.credential(from: Data((valid + "windsurf_api_key = \"duplicate\"").utf8)) == nil)
    #expect(DevinUsageProvider.credential(from: Data(repeating: 65, count: 65_537)) == nil)
}

@Test
func devinCollectsDirectlyWithOnlyItsOwnLoginAndRejectsAuthFailure() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let credential = directory.appendingPathComponent("credentials.toml")
    try Data("api_server_url = \"https://server.codeium.com\"\nwindsurf_api_key = \"test-credential\"".utf8).write(to: credential)
    for status in [200, 401] {
        let provider = DevinUsageProvider(credentialURL: credential, loader: { request in
            #expect(request.url?.host == "server.codeium.com")
            #expect(request.url?.path.hasSuffix("/GetUserStatus") == true)
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Connect-Protocol-Version") == "1")
            let body = try JSONSerialization.jsonObject(with: #require(request.httpBody)) as? [String: [String: String]]
            #expect(body?["metadata"]?["apiKey"] == "test-credential")
            return (devinFixture, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }, versionReader: { "3000.6.11" })
        let result = await provider.read()
        #expect(result.status == (status == 200 ? .live : .needsAuth))
        #expect(status == 200 || result.windows.isEmpty)
        if status == 200 { #expect(result.windows.map(\.usedPercent) == [6, 8]) }
        #expect(result.source == "devin_user_status")
    }
}

@Test
func cubicReportsPreserveObservationTimeAndRejectExpiredSpoofedOrSupersededReports() {
    let reading = CubicUsageProvider.parse([cubicCheck()], repository: "owner/repo", now: sampleNow)
    #expect(reading.windows.first?.used == 302_778)
    #expect(reading.windows.first?.limit == 300_000)
    #expect(abs((reading.windows.first?.usedPercent ?? 0) - 100.926) < 0.0001)
    #expect(reading.observedAt == reportDate)
    #expect(reading.error == "Last reported by Cubic; not a live balance")
    #expect(CubicUsageProvider.parse([cubicCheck()], repository: "owner/repo", now: sampleNow.addingTimeInterval(20 * 86400)).windows.isEmpty)
    var spoof = cubicCheck()
    spoof["app"] = ["id": 123, "slug": "cubic-dev-ai"]
    #expect(CubicUsageProvider.parse([spoof], repository: "owner/repo", now: sampleNow).windows.isEmpty)
    var newer = cubicCheck(summary: "Review complete. No quota reported.")
    newer["completed_at"] = "2026-09-08T00:59:00Z"
    #expect(CubicUsageProvider.parse([cubicCheck(), newer], repository: "owner/repo", now: sampleNow).windows.isEmpty)
}

@Test
func cubicFetchesGitHubDirectlyAndNeverRunsAReview() async throws {
    let provider = CubicUsageProvider(repository: { "owner/repo" }, runner: { command, timeout, limit in
        #expect(command.count == 7)
        #expect(command.prefix(6) == ["/test/gh", "api", "--hostname", "github.com", "--method", "GET"])
        #expect(timeout <= 10 && limit == 1_048_576)
        let payload: Any
        if command.last!.contains("/pulls?") {
            payload = [["head": ["sha": String(repeating: "a", count: 40)]]]
        } else {
            #expect(command.last!.contains("/check-runs?") == true)
            payload = ["check_runs": [cubicCheck()]]
        }
        return BillingCommandResult(exitCode: 0, stdout: try! JSONSerialization.data(withJSONObject: payload))
    }, executable: "/test/gh", now: { sampleNow })
    // Report dates are deliberately historic: a fetch must not stamp them as freshly observed.
    let reading = await provider.read()
    #expect(reading.observedAt == reportDate)
    #expect(reading.source == "cubic_github_check")
    for invalid in ["", "../repo", "owner/..", "https://github.com/owner/repo", "owner/repo?x=1", "owner/repo/extra"] {
        #expect(!CubicUsageProvider.validRepository(invalid))
    }
}

@MainActor
@Test
func cubicSourcePersistsAndChangingOrganizationClearsOldCapacity() {
    let name = "NightCrawlerTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    let store = UsageStore(providers: [], defaults: defaults)
    store.readings = [CubicUsageProvider.parse([cubicCheck()], repository: "owner/repo", now: sampleNow)]
    store.setCubicUsageRepository("another/repo")
    #expect(store.readings.isEmpty)
    #expect(UsageStore(providers: [], defaults: defaults).cubicUsageRepository == "another/repo")
}

private actor PendingCubicRead: UsageProvider {
    nonisolated let id = "cubic"
    nonisolated let label = "Cubic"
    nonisolated var isAvailable: Bool { true }
    private var continuation: CheckedContinuation<UsageReading, Never>?
    private var called = false
    var started: Bool { continuation != nil }
    func read() async -> UsageReading {
        if called {
            return CubicUsageProvider.parse([], repository: "new/repo")
        }
        called = true
        return await withCheckedContinuation { continuation = $0 }
    }
    func finishOldRequest() {
        continuation?.resume(returning: CubicUsageProvider.parse([cubicCheck()], repository: "old/repo", now: sampleNow))
        continuation = nil
    }
}

@MainActor
@Test
func changingCubicSourceDropsAnInFlightOldOrganizationResponse() async throws {
    let name = "NightCrawlerTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    defaults.set("old/repo", forKey: CubicUsageProvider.repositoryKey)
    defaults.set(try! JSONEncoder().encode([
        RoutingToolState(id: "cubic", label: "Cubic", enabled: true, available: false)
    ]), forKey: "routingToolStates")
    for pollAll in [false, true] {
        defaults.set("old/repo", forKey: CubicUsageProvider.repositoryKey)
        let provider = PendingCubicRead()
        let store = UsageStore(providers: [provider], defaults: defaults)
        try #require(store.isProviderEnabled("cubic"))
        let task = Task { if pollAll { await store.poll() } else { await store.refresh(providerId: "cubic") } }
        let deadline = Date().addingTimeInterval(3)
        while !(await provider.started), Date() < deadline { try await Task.sleep(for: .milliseconds(5)) }
        try #require(await provider.started)
        store.setCubicUsageRepository("new/repo")
        await provider.finishOldRequest()
        await task.value
        #expect(store.readings.first { $0.providerId == "cubic" }?.windows.isEmpty != false,
                "a request started for the previous organization must not repopulate its quota")
    }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["NIGHTCRAWLER_LIVE_PROVIDERS"] == "1"))
func standaloneLiveProviderSmoke() async {
    let devin = await DevinUsageProvider().read()
    #expect(devin.status == .live, "direct Devin quota must work without a Dino snapshot")
    #expect(!devin.windows.isEmpty)
    let cubic = await CubicUsageProvider(repository: { "think-basis-inc/nightcrawler" }).read()
    #expect(cubic.source == "cubic_github_check")
    #expect(!cubic.windows.isEmpty, "read the existing Cubic report directly; never trigger a review")
}
