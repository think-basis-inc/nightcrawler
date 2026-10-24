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

private func cubicGraphQLPayload(runs: [[String: Any]]) -> [String: Any] {
    [
        "data": [
            "search": [
                "nodes": runs.map { run in
                    [
                        "commits": [
                            "nodes": [
                                [
                                    "commit": [
                                        "checkSuites": [
                                            "nodes": [
                                                [
                                                    "app": ["databaseId": 1_082_092, "slug": "cubic-dev-ai"],
                                                    "checkRuns": ["nodes": [run]],
                                                ]
                                            ]
                                        ]
                                    ]
                                ]
                            ]
                        ]
                    ] as [String: Any]
                }
            ]
        ]
    ]
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

@MainActor
@Test
func cubicIconKeepsALiveAllowanceAfterReviewsResumeWithoutANewLineCount() {
    let resumeNow = ProviderHelpers.parseISO8601("2026-09-18T03:50:00Z")!
    var resumed = cubicCheck(summary: "AI review completed with 1 review. Found 1 issue across 5 files.")
    resumed["completed_at"] = "2026-09-18T03:49:51Z"
    let reading = CubicUsageProvider.parse([cubicCheck(), resumed], repository: "owner/repo", now: resumeNow)
    #expect(reading.status == .live)
    #expect(reading.windows.first?.used == 0)
    #expect(reading.windows.first?.limit == 300_000)
    #expect(reading.windows.first?.usedPercent == 0)
    #expect(reading.windows.first?.resetsAt == ProviderHelpers.parseISO8601("2026-10-17T00:00:00Z"))
    #expect(reading.observedAt == ProviderHelpers.parseISO8601("2026-09-18T03:49:51Z"))
    #expect(ProviderIcon.percentageText(for: reading, now: resumeNow) == "0.0%")
}

@Test
func cubicReadsOrgReviewsAfterTheMonthlyAllowanceResets() async throws {
    let resumeNow = ProviderHelpers.parseISO8601("2026-09-18T03:50:00Z")!
    let provider = CubicUsageProvider(repository: { "owner/repo" }, apiKey: { .missing }, runner: { command, timeout, limit in
        #expect(command.prefix(4) == ["/test/gh", "api", "--hostname", "github.com"])
        #expect(!command.contains { $0.localizedCaseInsensitiveContains("mutation") })
        #expect(timeout <= 10 && limit == 1_048_576)
        if command.contains("graphql") {
            #expect(command.contains { $0.contains("org:owner") })
            let payload = cubicGraphQLPayload(runs: [
                [
                    "name": "cubic · AI code reviewer",
                    "status": "COMPLETED",
                    "completedAt": "2026-09-18T03:49:51Z",
                    "conclusion": "SUCCESS",
                    "summary": "AI review completed with 1 review. Found 1 issue across 5 files.",
                    "title": "AI review completed",
                ],
                [
                    "name": "cubic · AI code reviewer",
                    "status": "COMPLETED",
                    "completedAt": "2026-09-07T20:21:26Z",
                    "conclusion": "NEUTRAL",
                    "summary": "cubic has reviewed 302,778 of the 300,000 allowed lines of code this month. Reviews resume on 17 September 2026 (in 10 days).",
                    "title": "AI review line limit reached",
                ],
            ])
            return BillingCommandResult(exitCode: 0, stdout: try! JSONSerialization.data(withJSONObject: payload))
        }
        return BillingCommandResult(exitCode: 1, stdout: Data())
    }, executable: "/test/gh", now: { resumeNow })
    let reading = await provider.read()
    #expect(reading.windows.first?.used == 0)
    #expect(reading.windows.first?.limit == 300_000)
    #expect(reading.windows.first?.usedPercent == 0)
}

@Test
func cubicFetchesGitHubDirectlyAndNeverRunsAReview() async throws {
    let provider = CubicUsageProvider(repository: { "owner/repo" }, apiKey: { .missing }, runner: { command, timeout, limit in
        #expect(command.prefix(4) == ["/test/gh", "api", "--hostname", "github.com"])
        #expect(!command.contains { $0.localizedCaseInsensitiveContains("mutation") })
        #expect(timeout <= 10 && limit == 1_048_576)
        let payload: Any
        if command.contains("graphql") {
            #expect(command.contains { $0.contains("org:owner") })
            payload = cubicGraphQLPayload(runs: [[
                "name": "cubic · AI code reviewer",
                "status": "COMPLETED",
                "completedAt": "2026-09-07T20:21:26Z",
                "conclusion": "NEUTRAL",
                "summary": "cubic has reviewed 302,778 of the 300,000 allowed lines of code this month. Reviews resume on 17 September 2026 (in 10 days).",
                "title": "AI review line limit reached",
            ]])
        } else if command.last!.contains("/pulls?") {
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

private func cubicSubscriptionFixture() -> [String: Any] { [
    "jsonrpc": "2.0", "id": 1,
    "result": [
        "content": [["type": "text", "text": "{}"]],
        "structuredContent": [
            "provider": "stripe", "plan": "pro", "status": "active", "organization": "owner",
            "seats": ["purchased": 1, "assigned": 1, "available": 0],
            "reviewUsage": ["used": 51_820, "limit": 80_000, "resetsAt": "2026-11-17T05:20:42.000Z"],
            "pendingChange": NSNull(),
        ],
    ],
] }

private func cubicAPIProvider(status: Int = 200, body: Any = cubicSubscriptionFixture(),
                              key: Keychain.Lookup = .found(Data("cbk_test-key\n".utf8)),
                              now: Date = sampleNow,
                              onRequest: @escaping @Sendable (URLRequest) -> Void = { _ in }) -> CubicUsageProvider {
    let data = try! JSONSerialization.data(withJSONObject: body)
    return CubicUsageProvider(repository: { "owner/repo" }, apiKey: { key }, loader: { request in
        onRequest(request)
        return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }, runner: { _, _, _ in
        Issue.record("a stored Cubic API key must not fall back to GitHub check reports")
        return BillingCommandResult(exitCode: 1, stdout: Data())
    }, executable: "/test/gh", now: { now })
}

@MainActor
@Test
func cubicReadsLiveReviewedLinesFromCubicWhenAnAPIKeyIsStored() async throws {
    let reading = await cubicAPIProvider(onRequest: { request in
        #expect(request.url?.absoluteString == "https://www.cubic.dev/api/mcp")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer cbk_test-key")
        let body = try? JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
        #expect(body?["method"] as? String == "tools/call")
        let params = body?["params"] as? [String: Any]
        #expect(params?["name"] as? String == "get_subscription")
        #expect((params?["arguments"] as? [String: String]) == ["organization": "owner"])
    }).read()
    #expect(reading.status == .live)
    #expect(reading.source == "cubic_api")
    #expect(reading.error == nil)
    #expect(reading.observedAt == sampleNow)
    let window = try #require(reading.windows.first)
    #expect(window.id == "reviewed_lines")
    #expect(window.used == 51_820)
    #expect(window.limit == 80_000)
    #expect(abs(window.usedPercent - 64.775) < 0.0001)
    #expect(window.resetsAt == ProviderHelpers.parseISO8601("2026-11-17T05:20:42Z"))
    #expect(ProviderIcon.percentageText(for: reading, now: sampleNow) == "64.8%")
}

@Test
func cubicRejectedUnreadableOrLockedAPIKeyIsACubicErrorNotAGitHubSignIn() async {
    // The remedy is a new Cubic key, which `gh auth login` cannot provide; a
    // sign-in watch would also resend the rejected key every few seconds.
    var readings = [UsageReading]()
    for status in [401, 403] {
        readings.append(await cubicAPIProvider(status: status, body: ["error": "invalid_token"]).read())
    }
    for key in [Keychain.Lookup.found(Data("not-a-cubic-key".utf8)), .unavailable] {
        readings.append(await cubicAPIProvider(key: key).read())
    }
    for reading in readings {
        #expect(reading.status.isError)
        #expect(reading.source == "cubic_api")
        #expect(reading.windows.isEmpty)
        #expect(!reading.isSignedOut)
        #expect(HUDIconAction.resolve(for: reading, isInstalled: { _ in true }) == .toggleDetail)
    }
}

private final class KeychainLookupCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var lookups: Int { lock.withLock { count } }
    func deny() -> Keychain.Lookup { lock.withLock { count += 1 }; return .denied }
}

@MainActor
@Test
func cubicKeychainDenialIsNotPromptedAgainByPollingAndOffersRetry() async throws {
    let name = "NightCrawlerTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    defaults.set("owner/repo", forKey: CubicUsageProvider.repositoryKey)
    defaults.set(try JSONEncoder().encode([
        RoutingToolState(id: "cubic", label: "Cubic", enabled: true, available: true)
    ]), forKey: "routingToolStates")
    let counter = KeychainLookupCounter()
    let provider = CubicUsageProvider(repository: { "owner/repo" }, apiKey: { counter.deny() }, loader: { _ in
        throw URLError(.badURL)
    }, runner: { _, _, _ in
        Issue.record("a denied Cubic key must not fall back to GitHub check reports")
        return BillingCommandResult(exitCode: 1, stdout: Data())
    }, executable: "/test/gh", now: { sampleNow })
    let store = UsageStore(providers: [provider], defaults: defaults)
    try #require(store.isProviderEnabled("cubic"))

    await store.poll()
    await store.poll()

    #expect(counter.lookups == 1, "a denied Keychain prompt must not be raised again by the next poll")
    let reading = try #require(store.readings.first { $0.providerId == "cubic" })
    #expect(reading.source == UsageReading.keychainDeniedSource)
    #expect(HUDIconAction.resolve(for: reading, isInstalled: { _ in true }) == .toggleDetail)
    #expect(HUDIconAction.shouldRetry(for: reading, opensDetail: true))
}

@Test
func cubicAPIUsageGoesStaleLikeOtherPolledProvidersInsteadOfUntilReset() async throws {
    let reading = await cubicAPIProvider().read()
    #expect(reading.isFreshlyObserved(now: sampleNow))
    #expect(!reading.isFreshlyObserved(now: sampleNow.addingTimeInterval(3600)),
            "a revoked key or Cubic outage must not keep an hour-old balance live until the monthly reset")
}

@Test
func cubicNeverReportsZeroUsageFromAMalformedOrFailedAPIResponse() async {
    func subscription(_ usage: Any?) -> [String: Any] {
        var content: [String: Any] = ["plan": "pro"]
        if let usage { content["reviewUsage"] = usage }
        return ["jsonrpc": "2.0", "id": 1, "result": ["structuredContent": content]]
    }
    let reset = "2026-11-17T05:20:42.000Z"
    let bodies: [(Int, Any)] = [
        (500, cubicSubscriptionFixture()),
        (200, ["jsonrpc": "2.0", "id": 1, "error": ["code": -32000, "message": "nope"]]),
        (200, ["jsonrpc": "2.0", "id": 1, "result": ["isError": true, "structuredContent": cubicSubscriptionFixture()]]),
        (200, subscription(nil)),
        (200, subscription(["used": 0, "limit": 0, "resetsAt": reset])),
        (200, subscription(["used": -1, "limit": 80_000, "resetsAt": reset])),
        (200, subscription(["used": "51820", "limit": 80_000, "resetsAt": reset])),
        (200, subscription(["used": 0, "limit": 80_000])),
        (200, subscription(["used": 0, "limit": 80_000, "resetsAt": "2026-09-01T00:00:00Z"])),
    ]
    for (status, body) in bodies {
        let reading = await cubicAPIProvider(status: status, body: body).read()
        #expect(reading.windows.isEmpty, "status \(status) body \(body) must not produce a usage window")
        #expect(reading.status != .live)
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
    #expect(cubic.status == .live)
    #expect(!cubic.windows.isEmpty, "read Cubic usage directly; never trigger a review")
}
