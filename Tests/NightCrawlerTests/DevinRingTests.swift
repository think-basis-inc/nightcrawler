import Foundation
import Testing
@testable import NightCrawler

@Test(arguments: [25, 85])
func devinRingsKeepWeeklyOutsideAndDailyInside(dailyUsed: Int) throws {
    let data = Data("{\"userStatus\":{\"planStatus\":{\"dailyQuotaRemainingPercent\":\(100 - dailyUsed),\"weeklyQuotaRemainingPercent\":60}},\"planInfo\":{\"billingStrategy\":\"BILLING_STRATEGY_QUOTA\"}}".utf8)
    let reading = DevinUsageProvider.parse(data)
    #expect(try #require(reading.outerRingWindow).id == "weekly")
    #expect(reading.outerRingWindow?.usedPercent == 40)
    #expect(try #require(reading.innerRingWindow).id == "daily")
    #expect(reading.innerRingWindow?.usedPercent == Double(dailyUsed))
}

@Test
func devinMissingQuotaDoesNotDuplicateTheOtherRing() {
    for period in ["daily", "weekly"] {
        let data = Data("{\"userStatus\":{\"planStatus\":{\"\(period)QuotaRemainingPercent\":60}},\"planInfo\":{\"billingStrategy\":\"BILLING_STRATEGY_QUOTA\"}}".utf8)
        let reading = DevinUsageProvider.parse(data)
        #expect(reading.outerRingWindow?.id == (period == "weekly" ? "weekly" : nil))
        #expect(reading.innerRingWindow?.id == (period == "daily" ? "daily" : nil))
    }
}
