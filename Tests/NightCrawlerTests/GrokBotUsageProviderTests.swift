import Foundation
import Testing
@testable import NightCrawler

@Test
func grokBotMapsWeeklyPercentAndResetFromSandStatus() throws {
    let root: [String: Any] = [
        "currentPeriodStart": "2026-09-09T04:34:11.479Z",
        "nextResetTimestampUtc": "2026-09-16T04:34:11.479Z",
        "usagePercent": 10.417556,
        "hasAvailableUsage": true,
        "hasNonZeroIncludedLimit": true,
        "grokPlanLabel": "Grok Bot Plan",
    ]

    let windows = try #require(GrokBotUsageProvider.windows(from: root))

    #expect(windows.map(\.id) == ["weekly"])
    #expect(windows.map(\.label) == ["Weekly usage"])
    #expect(windows.map(\.usedPercent) == [10.417556])
    #expect(windows.first?.windowMinutes == 10_080)
    #expect(windows.first?.resetsAt == ProviderHelpers.parseISO8601("2026-09-16T04:34:11.479Z"))
}

@Test
func grokBotHidesPooledEnterpriseAllowance() {
    let root: [String: Any] = [
        "usagePercent": 10.4,
        "hasNonZeroIncludedLimit": true,
        "usesPooledEnterpriseAllowance": true,
        "nextResetTimestampUtc": "2026-09-16T04:34:11.479Z",
    ]

    #expect(GrokBotUsageProvider.windows(from: root) == nil)
}

@Test
func grokBotUsesCursorEditorSessionNotGrokCLI() async {
    let cache = CursorSessionCache()
    let token = grokBotTestJWT(sub: "auth0|user_01GROKBOT")
    await cache.store(
        CursorUsageProvider.Credentials(
            accountID: "cached",
            cookie: "WorkosCursorSessionToken=user_01GROKBOT::\(token)",
            accessToken: token
        )
    )
    let provider = GrokBotUsageProvider(
        storeReader: {
            Issue.record("a cached Cursor session must not re-open the editor store")
            return ProcessRunner.RunResult(output: Data(), exitCode: 5)
        },
        loader: { request in
            #expect(request.url == GrokBotUsageProvider.usageURL)
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(token)")
            #expect(request.value(forHTTPHeaderField: "Connect-Protocol-Version") == "1")
            return (grokBotUsageJSON(), grokBotUsageResponse())
        },
        sessionCache: cache
    )

    let reading = await provider.read()

    #expect(reading.providerId == "grokbot")
    #expect(reading.label == "Grok Bot")
    #expect(reading.status == .live)
    #expect(reading.windows.contains { $0.id == "weekly" && abs($0.usedPercent - 10.417556) < 0.0001 })
}

private func grokBotTestJWT(sub: String) -> String {
    func encode(_ object: [String: String]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: object)
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }
    return "\(encode(["alg": "none"])).\(encode(["sub": sub])).sig"
}

private func grokBotUsageJSON() -> Data {
    let root: [String: Any] = [
        "currentPeriodStart": "2026-09-09T04:34:11.479Z",
        "nextResetTimestampUtc": "2026-09-16T04:34:11.479Z",
        "usagePercent": 10.417556,
        "hasAvailableUsage": true,
        "hasNonZeroIncludedLimit": true,
    ]
    return try! JSONSerialization.data(withJSONObject: root)
}

private func grokBotUsageResponse() -> HTTPURLResponse {
    HTTPURLResponse(
        url: GrokBotUsageProvider.usageURL,
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
    )!
}
