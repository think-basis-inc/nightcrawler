import Foundation
import Testing
@testable import NightCrawler

@Test
func resetCaptionIncludesCalendarDateAndClockTimeNotJustRelativeDay() {
    let timeZone = TimeZone(identifier: "America/Toronto")!
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime]
    let now = iso.date(from: "2026-09-10T06:00:00Z")!
    let reset = iso.date(from: "2026-09-11T18:59:59Z")!

    let caption = ResetClock.caption(
        for: reset,
        now: now,
        timeZone: timeZone,
        locale: Locale(identifier: "en_CA")
    )

    #expect(caption.contains("Sep"))
    #expect(caption.contains("11"))
    #expect(
        caption.contains("2:59") || caption.contains("14:59"),
        "must show the clock time, not only 'in 1 day'"
    )
    #expect(caption.localizedCaseInsensitiveContains("in 1 day") == false)
}

@Test
func usageCaptionNamesUsedAndRemainingSoVendorRemainingIsNotMistakenForUsed() {
    let window = UsageWindow(
        id: "included",
        label: "Included usage",
        used: 4_795,
        limit: 10_000,
        usedPercent: 47.95457142857143,
        windowMinutes: 43_200,
        resetsAt: Date(timeIntervalSince1970: 1_789_015_004)
    )

    let line = UsageCaption.line(for: window)

    #expect(line.localizedCaseInsensitiveContains("used"))
    #expect(line.contains("48.0%"))
    #expect(line.contains("52.0%"))
    #expect(line.localizedCaseInsensitiveContains("left") || line.localizedCaseInsensitiveContains("remaining"))
}
