import Foundation
import Testing
@testable import NightCrawler

private let sampleUtilizationJSON = """
{
    "cachedUsageUtilization": {
        "fetchedAtMs": 1788844861042,
        "utilization": {
            "five_hour": {
                "utilization": 7,
                "resets_at": "2026-09-08T06:50:00.030171+00:00"
            },
            "seven_day": {
                "utilization": 59,
                "resets_at": "2026-09-11T19:00:00.030192+00:00"
            },
            "limits": [
                {
                    "kind": "session",
                    "percent": 7,
                    "resets_at": "2026-09-08T06:50:00.030171+00:00"
                },
                {
                    "kind": "weekly_all",
                    "percent": 59,
                    "resets_at": "2026-09-11T19:00:00.030192+00:00"
                },
                {
                    "kind": "weekly_scoped",
                    "percent": 94,
                    "resets_at": "2026-09-11T19:00:00.030410+00:00",
                    "scope": { "model": { "display_name": "Fable" } }
                }
            ]
        }
    }
}
"""

@Test
func claudeLocalUsageCacheReadsSubscriptionWindowsFromClaudeCodeJSON() throws {
    let now = Date(timeIntervalSince1970: 1_788_850_000)
    let windows = ClaudeLocalUsageCache.windows(from: Data(sampleUtilizationJSON.utf8), now: now)

    #expect(windows.contains { $0.id == "session" && $0.usedPercent == 7 })
    #expect(windows.contains { $0.id == "weekly_all" && $0.usedPercent == 59 })
    #expect(windows.contains { $0.id == "weekly_scoped" && $0.usedPercent == 94 })
    #expect(windows.first { $0.id == "weekly_scoped" }?.label == "Fable")
}

private final class OAuthCallSpy: @unchecked Sendable {
    var called = false
}

@Test
func claudeProviderPrefersLocalCacheOverOAuthSoMonitoringDoesNotNeedALiveConnection() async {
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
    let cache = ClaudeLocalUsageCache(
        fileURL: URL(fileURLWithPath: "/fixture/claude.json"),
        reader: { _ in Data(sampleUtilizationJSON.utf8) }
    )
    let spy = OAuthCallSpy()
    let provider = ClaudeCodeUsageProvider(
        credentials: credentials,
        localUsage: cache,
        sessionDataLoader: { _ in
            spy.called = true
            throw URLError(.notConnectedToInternet)
        },
        cliWindowsReader: { [] }
    )

    let reading = await provider.read()

    #expect(!spy.called)
    #expect(reading.status == .live)
    #expect(reading.source == "claude_local_cache")
    #expect(reading.windows.contains { $0.id == "weekly_scoped" && $0.usedPercent == 94 })
}

@Test
func claudeLocalUsageCacheIgnoresStaleClaudeCodeSnapshots() {
    let now = Date(timeIntervalSince1970: 1_788_850_000 + (25 * 60 * 60))
    let windows = ClaudeLocalUsageCache.windows(from: Data(sampleUtilizationJSON.utf8), now: now)
    #expect(windows.isEmpty)
}

@MainActor
@Test
func claudeProviderUsesLocalClaudeCodeCacheWhenCLIReturnsAPIBillingSession() async {
    let credentials = ClaudeCredentialStore(
        fileURL: URL(fileURLWithPath: "/missing/credentials.json"),
        reader: { _ in nil }
    )
    let cache = ClaudeLocalUsageCache(
        fileURL: URL(fileURLWithPath: "/fixture/claude.json"),
        reader: { _ in Data(sampleUtilizationJSON.utf8) }
    )
    let provider = ClaudeCodeUsageProvider(
        credentials: credentials,
        localUsage: cache,
        cliWindowsReader: { [] }
    )

    let reading = await provider.read()

    #expect(reading.status == .live)
    #expect(reading.source == "claude_local_cache")
    #expect(reading.windows.contains { $0.id == "weekly_all" && $0.usedPercent == 59 })
    #expect(reading.innerRingWindow?.usedPercent == 94)
    #expect(ProviderIcon.percentageText(for: reading) != nil)
}
