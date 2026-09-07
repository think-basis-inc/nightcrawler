import Testing
@testable import NightCrawler

@Test
func readingFractionIsClamped() {
    let r = UsageReading(
        providerId: "x",
        label: "X",
        percentUsed: 150,
        used: 3,
        limit: 2,
        windowName: "w",
        resetsAt: nil,
        status: .ok
    )
    #expect(r.fraction == 1.0)
}
