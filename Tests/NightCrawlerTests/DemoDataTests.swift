import Testing
@testable import NightCrawler

@Test
func demoDataHasMultipleProviders() {
    #expect(DemoData.readings.count > 1)
}

@Test
func demoDataIncludesCriticalUsage() {
    let copilot = DemoData.readings.first { $0.providerId == "copilot" }
    #expect(copilot != nil)
    #expect(copilot?.headlineWindow?.fraction == 0.98)
}
