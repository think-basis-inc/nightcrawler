import Testing
@testable import NightCrawler

@Test
func windowFractionIsClamped() {
    let w = UsageWindow(
        id: "x",
        label: "X",
        used: 3,
        limit: 2,
        usedPercent: 150,
        windowMinutes: nil,
        resetsAt: nil
    )
    #expect(w.fraction == 1.0)
}

@Test
func windowStatusFromFraction() {
    let ok = UsageWindow(id: "a", label: "A", used: 30, limit: 100, usedPercent: 30, windowMinutes: nil, resetsAt: nil)
    let warning = UsageWindow(id: "b", label: "B", used: 60, limit: 100, usedPercent: 60, windowMinutes: nil, resetsAt: nil)
    let critical = UsageWindow(id: "c", label: "C", used: 75, limit: 100, usedPercent: 75, windowMinutes: nil, resetsAt: nil)
    #expect(ok.status == .ok)
    #expect(warning.status == .warning)
    #expect(critical.status == .critical)
}
