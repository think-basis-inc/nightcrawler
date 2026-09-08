import Foundation
import Testing
@testable import NightCrawler

private func emptyLocalUsageCache() -> ClaudeLocalUsageCache {
    ClaudeLocalUsageCache(
        fileURL: URL(fileURLWithPath: "/missing/claude.json"),
        reader: { _ in nil }
    )
}

private let sampleToken = "test-subscription-token"

private func credentialJSON(
    token: String = sampleToken,
    expiresAt: Double = (Date().timeIntervalSince1970 + 3600) * 1000
) -> Data {
    let payload: [String: Any] = [
        "claudeAiOauth": [
            "accessToken": token,
            "expiresAt": expiresAt,
            "subscriptionType": "max",
        ]
    ]
    return try! JSONSerialization.data(withJSONObject: payload)
}

private final class CLISpy: @unchecked Sendable {
    var called = false
    func read() -> [UsageWindow] {
        called = true
        return []
    }
}

@Test
func successfulOAuthPayloadMissingFableIsAugmentedWithClaudeCLIUsageClientsFableWindow() async throws {
    let credentials = ClaudeCredentialStore(
        fileURL: URL(fileURLWithPath: "/fixture/credentials.json"),
        reader: { _ in credentialJSON() }
    )

    let cliOutput = """
    Current session
    0% 0% used
    Resets 9:50pm (America/Toronto)
    Current week (all models)
    54% 54% used
    Resets Sep 11 at 3pm (America/Toronto)
    Current week (Fable)
    85% 85% used
    Resets Sep 11 at 3pm (America/Toronto)
    """

    let cliUsage = ClaudeCLIUsageClient(
        command: ["/bin/sh", "-c", "printf '%s\n' \"\(cliOutput)\"; sleep 2"]
    )

    let oauthJSON = """
    {
        "five_hour": {
            "utilization": 5,
            "resets_at": "2026-09-07T21:50:00Z"
        },
        "seven_day": {
            "utilization": 54,
            "resets_at": "2026-09-11T15:00:00Z"
        }
    }
    """

    let httpResponse = HTTPURLResponse(
        url: URL(string: "https://api.anthropic.com/api/oauth/usage")!,
        statusCode: 200,
        httpVersion: "HTTP/1.1",
        headerFields: ["Content-Type": "application/json"]
    )!

    let provider = ClaudeCodeUsageProvider(
        credentials: credentials,
        localUsage: emptyLocalUsageCache(),
        cliUsage: cliUsage,
        sessionDataLoader: { _ in (Data(oauthJSON.utf8), httpResponse) }
    )

    let reading = await provider.read()

    #expect(reading.status == .live)
    #expect(reading.source == "claude_oauth_usage")
    #expect(reading.windows.contains { $0.id == "session" })
    #expect(reading.windows.contains { $0.id == "weekly_all" })
    #expect(reading.windows.contains { $0.id == "fable" })
    #expect(reading.innerRingWindow?.label == "Fable")
    #expect(reading.innerRingWindow?.usedPercent == 85)
    #expect(reading.windows.first { $0.id == "session" }?.usedPercent == 5)
    #expect(reading.windows.first { $0.id == "weekly_all" }?.usedPercent == 54)
}

@Test
func claudeOAuthRefreshDoesNotRequeryCLIWhenOAuthAlreadyIncludesFable() async throws {
    let credentials = ClaudeCredentialStore(
        fileURL: URL(fileURLWithPath: "/fixture/credentials.json"),
        reader: { _ in credentialJSON() }
    )

    let oauthJSON = """
    {
        "limits": [
            {
                "kind": "weekly_scoped",
                "percent": 42,
                "resets_at": "2026-09-11T15:00:00Z"
            }
        ],
        "five_hour": {
            "utilization": 10,
            "resets_at": "2026-09-07T21:50:00Z"
        },
        "seven_day": {
            "utilization": 50,
            "resets_at": "2026-09-11T15:00:00Z"
        }
    }
    """

    let httpResponse = HTTPURLResponse(
        url: URL(string: "https://api.anthropic.com/api/oauth/usage")!,
        statusCode: 200,
        httpVersion: "HTTP/1.1",
        headerFields: ["Content-Type": "application/json"]
    )!

    let spy = CLISpy()
    let provider = ClaudeCodeUsageProvider(
        credentials: credentials,
        localUsage: emptyLocalUsageCache(),
        sessionDataLoader: { _ in (Data(oauthJSON.utf8), httpResponse) },
        cliWindowsReader: { spy.read() }
    )

    let reading = await provider.read()

    #expect(!spy.called)
    #expect(reading.status == .live)
    #expect(reading.windows.contains { $0.id == "weekly_scoped" })
    #expect(reading.innerRingWindow?.label == "Fable")
    #expect(reading.innerRingWindow?.usedPercent == 42)
}

@Test
func claudeWindowAugmentationAppendsFableWhenMissing() {
    let oauth = [
        UsageWindow(id: "session", label: "Current session", used: 5, limit: 100, usedPercent: 5, windowMinutes: 300, resetsAt: nil),
        UsageWindow(id: "weekly_all", label: "All models", used: 54, limit: 100, usedPercent: 54, windowMinutes: 10080, resetsAt: nil),
    ]
    let cli = [
        UsageWindow(id: "session", label: "Current session", used: 0, limit: 100, usedPercent: 0, windowMinutes: 300, resetsAt: nil),
        UsageWindow(id: "weekly_all", label: "All models", used: 54, limit: 100, usedPercent: 54, windowMinutes: 10080, resetsAt: nil),
        UsageWindow(id: "fable", label: "Fable", used: 85, limit: 100, usedPercent: 85, windowMinutes: 10080, resetsAt: nil),
    ]

    let augmented = ClaudeCodeUsageProvider.augment(oauthWindows: oauth, with: cli)

    #expect(augmented.map(\.id) == ["session", "weekly_all", "fable"])
    #expect(augmented.first { $0.id == "fable" }?.usedPercent == 85)
}

@Test
func claudeWindowAugmentationLeavesWindowsUnchangedWhenOAuthAlreadyContainsFable() {
    let oauth = [
        UsageWindow(id: "session", label: "Current session", used: 5, limit: 100, usedPercent: 5, windowMinutes: 300, resetsAt: nil),
        UsageWindow(id: "weekly_scoped", label: "Fable", used: 40, limit: 100, usedPercent: 40, windowMinutes: 10080, resetsAt: nil),
    ]
    let cli = [
        UsageWindow(id: "fable", label: "Fable", used: 90, limit: 100, usedPercent: 90, windowMinutes: 10080, resetsAt: nil),
    ]

    let augmented = ClaudeCodeUsageProvider.augment(oauthWindows: oauth, with: cli)

    #expect(augmented.map(\.id) == ["session", "weekly_scoped"])
    #expect(augmented.first { $0.id == "weekly_scoped" }?.usedPercent == 40)
}

@Test
func claudeWindowAugmentationLeavesWindowsUnchangedWhenCLILacksFable() {
    let oauth = [
        UsageWindow(id: "session", label: "Current session", used: 5, limit: 100, usedPercent: 5, windowMinutes: 300, resetsAt: nil),
    ]
    let cli = [
        UsageWindow(id: "weekly_all", label: "All models", used: 54, limit: 100, usedPercent: 54, windowMinutes: 10080, resetsAt: nil),
    ]

    let augmented = ClaudeCodeUsageProvider.augment(oauthWindows: oauth, with: cli)

    #expect(augmented.map(\.id) == ["session"])
}
