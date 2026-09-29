import Foundation
import Testing
@testable import NightCrawler

@Test
func codexSessionRateLimitsRestoreUsageWhenTheOAuthEndpointRejectsItsToken() throws {
    let line = #"{"timestamp":"2026-09-07T20:54:00.279Z","payload":{"rate_limits":{"plan_type":"pro","primary":{"resets_at":1789399908,"used_percent":17.0,"window_minutes":10080},"secondary":null}}}"#

    let reading = try #require(CodexSessionUsageReader.parse(line: line))

    #expect(reading.status == .live)
    #expect(reading.source == "codex_session_rate_limits")
    #expect(reading.authMode == "subscription")
    #expect(reading.windows.count == 1)
    #expect(reading.windows[0].label == "Weekly limit")
    #expect(reading.windows[0].usedPercent == 17)
    #expect(reading.windows[0].windowMinutes == 10_080)
    #expect(reading.observedAt == ProviderHelpers.parseISO8601("2026-09-07T20:54:00.279Z"))
}

@Test
func codexSessionOlderThanLiveFreshnessMustNotSkipTheLiveEndpoint() {
    let observed = Date()
    let reading = UsageReading(
        providerId: "codex",
        label: "Codex CLI",
        accountId: nil,
        authMode: "subscription",
        source: "codex_session_rate_limits",
        windows: [
            UsageWindow(id: "primary", label: "Weekly limit", used: 1700, limit: 10_000, usedPercent: 17, windowMinutes: 10_080, resetsAt: nil),
        ],
        status: .live,
        observedAt: observed,
        error: nil
    )

    #expect(CodexCLIUsageProvider.sessionIsFresh(reading, now: observed.addingTimeInterval(30)))
    #expect(CodexCLIUsageProvider.sessionIsFresh(reading, now: observed.addingTimeInterval(3 * 60)) == false)
}

@Test
func codexSessionReaderIgnoresUnrelatedTranscriptEvents() {
    let line = #"{"timestamp":"2026-09-07T20:54:00.279Z","payload":{"type":"message","text":"not quota data"}}"#
    #expect(CodexSessionUsageReader.parse(line: line) == nil)
}

@Test
func codexExpiredLoginReportsSignInInsteadOfAnOldSessionReading() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("NightCrawlerTests.\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let now = Date()
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let day = calendar.dateComponents([.year, .month, .day], from: now)
    let sessions = root.appendingPathComponent("sessions")
    let dayDirectory = sessions.appendingPathComponent(String(format: "%04d/%02d/%02d", day.year!, day.month!, day.day!))
    try FileManager.default.createDirectory(at: dayDirectory, withIntermediateDirectories: true)
    let observed = ISO8601DateFormatter().string(from: now.addingTimeInterval(-86_400))
    let resetsAt = Int(now.addingTimeInterval(3 * 86_400).timeIntervalSince1970)
    let line = #"{"timestamp":"\#(observed)","payload":{"rate_limits":{"plan_type":"pro","primary":{"resets_at":\#(resetsAt),"used_percent":8.0,"window_minutes":10080},"secondary":null}}}"#
    try Data((line + "\n").utf8).write(to: dayDirectory.appendingPathComponent("rollout.jsonl"))

    let claims = try JSONSerialization.data(withJSONObject: ["exp": now.addingTimeInterval(-3600).timeIntervalSince1970])
    let token = "e30.\(claims.base64EncodedString()).sig"
    let auth = try JSONSerialization.data(withJSONObject: ["tokens": ["access_token": token, "account_id": "acct"]])
    let authURL = root.appendingPathComponent("auth.json")
    try auth.write(to: authURL)

    let provider = CodexCLIUsageProvider(
        sessionUsage: CodexSessionUsageReader(rootURL: sessions, now: now),
        authPath: authURL.path
    )
    let reading = await provider.read()

    #expect(reading.status == .needsAuth)
    #expect(reading.windows.isEmpty)
    #expect(reading.error?.contains("codex login") == true)
}
