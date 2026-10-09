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

// Devin's Connect JSON omits zero-valued fields, so an exhausted window arrives
// as a reset time with no remaining percent. This is the live Pro response shape.
@Test
func devinExhaustedWeeklyStillFillsTheOuterRing() throws {
    let data = Data("{\"userStatus\":{\"planStatus\":{\"dailyQuotaRemainingPercent\":67,\"dailyQuotaResetAtUnix\":\"1791532800\",\"weeklyQuotaResetAtUnix\":\"1791705600\"}},\"planInfo\":{\"billingStrategy\":\"BILLING_STRATEGY_QUOTA\"}}".utf8)
    let reading = DevinUsageProvider.parse(data)
    let weekly = try #require(reading.outerRingWindow)
    #expect(weekly.id == "weekly")
    #expect(weekly.usedPercent == 100)
    #expect(weekly.resetsAt == Date(timeIntervalSince1970: 1_791_705_600))
    #expect(reading.innerRingWindow?.usedPercent == 33)
}
