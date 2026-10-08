import Foundation
import Testing
@testable import NightCrawler

@Test
func cursorSessionUsesJWTSubjectWhenStripeMembershipIdIsMissing() throws {
    let token = cursorTestJWT(sub: "auth0|user_01CURSOR")
    let rows: [[String: String]] = [
        ["key": "cursorAuth/accessToken", "value": token],
    ]
    let data = try JSONSerialization.data(withJSONObject: rows)

    let session = CursorUsageProvider.session(fromSQLiteOutput: data, exitCode: 0)

    guard case .ready(let credentials) = session else {
        Issue.record("expected a usable session from the JWT subject")
        return
    }
    #expect(credentials.cookie == "WorkosCursorSessionToken=user_01CURSOR::\(token)")
}

@Test
func cursorBusySqliteStoreIsUnavailableNotAMissingLogin() {
    let session = CursorUsageProvider.session(fromSQLiteOutput: Data(), exitCode: 5)
    #expect(session == .unavailable)
}

@Test
func cursorBusySqliteStoreIsARefreshErrorNotASignOut() async {
    let provider = CursorUsageProvider(
        storeReader: { ProcessRunner.RunResult(output: Data(), exitCode: 5) },
        loader: { _ in
            Issue.record("a locked usage store must not be treated as signed-out and must not hit Cursor")
            throw URLError(.cancelled)
        },
        sessionCache: CursorSessionCache()
    )

    let reading = await provider.read()

    guard case .error(let message) = reading.status else {
        Issue.record("busy sqlite was reported as \(reading.status) instead of a refresh error")
        return
    }
    #expect(message.contains("busy") || message.contains("unreadable") || message.contains("store"))
    #expect(reading.status != .needsAuth)
}

@Test
func cursorCachedSessionSurvivesABusyUsageStore() async throws {
    let cache = CursorSessionCache()
    let token = cursorTestJWT(sub: "auth0|user_01CACHED")
    await cache.store(
        CursorUsageProvider.Credentials(
            accountID: "cached",
            cookie: "WorkosCursorSessionToken=user_01CACHED::\(token)",
            accessToken: token
        )
    )
    let provider = CursorUsageProvider(
        storeReader: { ProcessRunner.RunResult(output: Data(), exitCode: 5) },
        loader: { request in
            if request.url == GrokBotUsageProvider.usageURL {
                return (cursorSandUsageJSON(), cursorSandUsageResponse())
            }
            #expect(request.value(forHTTPHeaderField: "Cookie")?.contains("user_01CACHED") == true)
            return (cursorUsageSummaryJSON(), cursorUsageSummaryResponse())
        },
        sessionCache: cache
    )

    let reading = await provider.read()

    #expect(reading.status == .live)
    #expect(reading.windows.contains { $0.id == "weekly" } == false)
    #expect(reading.windows.contains { $0.id == "included" && abs($0.usedPercent - 56.3) < 0.001 })
    #expect(reading.windows.contains { $0.id == "api" && abs($0.usedPercent - 16.9) < 0.001 })
    #expect(reading.windows.contains { $0.id == "auto" } == false)
}

@Test
func cursorUsageSummaryFallsBackToDashboardCopyWhenPlanObjectIsMissing() throws {
    let root: [String: Any] = [
        "billingCycleStart": "2026-08-11T23:36:44.000Z",
        "billingCycleEnd": "2026-09-11T23:36:44.000Z",
        "autoModelSelectedDisplayMessage": "You've used 56% of your included total usage",
        "namedModelSelectedDisplayMessage": "You've used 17% of your included API usage",
    ]

    let windows = CursorUsageProvider.windows(from: root)

    #expect(windows == nil || windows?.isEmpty == true)
}

@Test
func cursorUsageSummaryReadsTeamPlanWhenIndividualUsageIsAbsent() throws {
    let root: [String: Any] = [
        "billingCycleStart": "2026-08-11T23:36:44.000Z",
        "billingCycleEnd": "2026-09-11T23:36:44.000Z",
        "teamUsage": [
            "plan": [
                "totalPercentUsed": 12.5,
                "autoPercentUsed": 18.0,
                "apiPercentUsed": 1.5,
            ],
        ],
    ]

    let windows = try #require(CursorUsageProvider.windows(from: root))

    #expect(windows.map(\.id) == ["included", "api"])
    #expect(windows.map(\.usedPercent) == [12.5, 1.5])
    #expect(windows.map(\.label) == ["Included models", "Other Models"])
}

@MainActor
@Test
func cursorRemainingAutoPercentIsInvertedToIncludedUsed() throws {
    let root: [String: Any] = [
        "billingCycleStart": "2026-08-11T23:36:44.000Z",
        "billingCycleEnd": "2026-09-11T23:36:44.000Z",
        "individualUsage": [
            "plan": [
                "autoPercentRemaining": 35.7,
            ],
        ],
    ]

    let windows = try #require(CursorUsageProvider.windows(from: root))
    #expect(windows.map(\.id) == ["included"])
    #expect(windows.map(\.usedPercent) == [64.3])
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
    #expect(try #require(reading.outerRingWindow).usedPercent == 64.3)
    #expect(reading.innerRingWindow == nil)
    #expect(ProviderIcon.percentageText(for: reading) == "64.3%")
    #expect(ProviderIcon.percentageText(for: windows[0]) == "64.3%")
}

@Test
func cursorLiveRefreshIsFasterThanTheSharedPoll() {
    #expect(CursorUsageProvider.liveRefreshInterval == 15)
    #expect(CursorUsageProvider.liveRefreshInterval < 60)
}

private func cursorTestJWT(sub: String) -> String {
    func encode(_ object: [String: String]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: object)
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }
    return "\(encode(["alg": "none"])).\(encode(["sub": sub])).sig"
}

private func cursorUsageSummaryJSON() -> Data {
    let root: [String: Any] = [
        "billingCycleStart": "2026-08-11T23:36:44.000Z",
        "billingCycleEnd": "2026-09-11T23:36:44.000Z",
        "individualUsage": [
            "plan": [
                "totalPercentUsed": 56.3,
                "autoPercentUsed": 62.9,
                "apiPercentUsed": 16.9,
            ],
        ],
    ]
    return try! JSONSerialization.data(withJSONObject: root)
}

private func cursorUsageSummaryResponse() -> HTTPURLResponse {
    HTTPURLResponse(
        url: CursorUsageProvider.usageSummaryURL,
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
    )!
}

private func cursorSandUsageJSON() -> Data {
    let root: [String: Any] = [
        "currentPeriodStart": "2026-09-09T04:34:11.479Z",
        "nextResetTimestampUtc": "2026-09-16T04:34:11.479Z",
        "usagePercent": 22.4,
        "hasNonZeroIncludedLimit": true,
        "grokPlanLabel": "Grok Bot Plan",
    ]
    return try! JSONSerialization.data(withJSONObject: root)
}

private func cursorSandUsageResponse() -> HTTPURLResponse {
    HTTPURLResponse(
        url: GrokBotUsageProvider.usageURL,
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
    )!
}
