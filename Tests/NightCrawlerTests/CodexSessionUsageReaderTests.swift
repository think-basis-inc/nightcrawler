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
func codexSessionReaderIgnoresUnrelatedTranscriptEvents() {
    let line = #"{"timestamp":"2026-09-07T20:54:00.279Z","payload":{"type":"message","text":"not quota data"}}"#
    #expect(CodexSessionUsageReader.parse(line: line) == nil)
}
