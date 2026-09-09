import Foundation
import Testing
@testable import NightCrawler

private func loadQuotaFixture() throws -> [String: Any] {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/copilot-quota.json")
    let data = try Data(contentsOf: url)
    let raw = try JSONSerialization.jsonObject(with: data)
    guard let dict = raw as? [String: Any] else {
        throw URLError(.cannotDecodeContentData)
    }
    return dict
}

private func finiteQuota() throws -> [String: Any] {
    var raw = try loadQuotaFixture()
    guard var snapshots = raw["quotaSnapshots"] as? [String: Any],
          var premium = snapshots["premium_interactions"] as? [String: Any]
    else {
        throw URLError(.cannotDecodeContentData)
    }
    premium["entitlementRequests"] = 300
    premium["usedRequests"] = 90
    premium["remainingPercentage"] = 70
    premium["resetDate"] = "2026-10-01T00:00:00Z"
    snapshots["premium_interactions"] = premium
    raw["quotaSnapshots"] = snapshots
    return raw
}

@Test
func copilotFiniteAllowanceBecomesUsageAndReset() throws {
    let result = CopilotQuotaParser.parse(try finiteQuota())
    #expect(result.status == .live, "Copilot finite subscription quota must populate a window")
    #expect(result.windows.count == 1)
    let window = try #require(result.windows.first)
    #expect(window.id == "premium_interactions")
    #expect(window.label == "Premium requests")
    #expect(window.usedPercent == 30)
    #expect(window.resetsAt?.timeIntervalSince1970 == 1_790_812_800)
}

@Test
func copilotZeroEntitlementStaysUnknown() throws {
    let result = CopilotQuotaParser.parse(try loadQuotaFixture())
    #expect(result.status == .unknown)
    #expect(result.windows.isEmpty)
}

@Test
func copilotMalformedQuotaStaysUnknown() {
    for invalid: Any in [NSNull(), [Any](), [String: Any](), ["quotaSnapshots": [Any]()]] {
        let result = CopilotQuotaParser.parse(invalid)
        #expect(result.windows.isEmpty, "malformed quota must not invent a 0/100 window")
    }
}

@Test
func copilotInvalidNumbersAndUnlimitedStayUnknown() throws {
    let fields: [(String, Any)] = [
        ("entitlementRequests", -1),
        ("entitlementRequests", true),
        ("remainingPercentage", Double.nan),
        ("remainingPercentage", -1),
        ("remainingPercentage", 101),
        ("remainingPercentage", "70"),
        ("usedRequests", -1),
        ("isUnlimitedEntitlement", true),
    ]
    for (field, value) in fields {
        var raw = try finiteQuota()
        guard var snapshots = raw["quotaSnapshots"] as? [String: Any],
              var premium = snapshots["premium_interactions"] as? [String: Any]
        else {
            throw URLError(.cannotDecodeContentData)
        }
        premium[field] = value
        snapshots["premium_interactions"] = premium
        raw["quotaSnapshots"] = snapshots
        let result = CopilotQuotaParser.parse(raw)
        #expect(result.windows.isEmpty, "\(field)=\(value) must not create a percentage")
    }
}

@Test
func copilotBadResetStaysUnknownNotInvented() throws {
    for value: Any in [NSNull(), "2026-10-01", "not-date", 1_790_812_800] {
        var raw = try finiteQuota()
        guard var snapshots = raw["quotaSnapshots"] as? [String: Any],
              var premium = snapshots["premium_interactions"] as? [String: Any]
        else {
            throw URLError(.cannotDecodeContentData)
        }
        premium["resetDate"] = value
        snapshots["premium_interactions"] = premium
        raw["quotaSnapshots"] = snapshots
        let window = try #require(CopilotQuotaParser.parse(raw).windows.first)
        #expect(window.resetsAt == nil, "bad reset must stay unknown")
        #expect(window.usedPercent == 30)
    }
}

@Test
func copilotBillingUsageBecomesMonthlyUsedPercentage() throws {
    let raw: [String: Any] = [
        "usageItems": [
            ["product": "Copilot", "grossQuantity": 41.0],
            ["product": "Actions", "grossQuantity": 999.0],
        ]
    ]
    let now = try #require(ISO8601DateFormatter().date(from: "2026-09-07T12:00:00Z"))

    let result = CopilotQuotaParser.parseBilling(raw, planLimit: 300, now: now)
    let window = try #require(result.windows.first)
    #expect(result.status == .live)
    #expect(window.label == "Monthly premium requests")
    #expect(abs(window.usedPercent - 13.6666666667) < 0.000001)
    #expect(window.resetsAt == ISO8601DateFormatter().date(from: "2026-10-01T00:00:00Z"))
}

@Test
func copilotEmptyBillingItemsDoNotInventZeroPercentOfTheConfiguredPlan() throws {
    let now = try #require(ISO8601DateFormatter().date(from: "2026-09-09T17:40:00Z"))
    let result = CopilotQuotaParser.parseBilling(
        ["usageItems": [Any](), "timePeriod": "2026-09"],
        planLimit: 300,
        now: now
    )

    #expect(result.windows.isEmpty, "empty GitHub billing items are not 0% of a Settings plan limit")
    #expect(result.status != .live)
}

@Test
func copilotUnlimitedCLIPlusEmptyBillingStaysUnknown() throws {
    var raw = try loadQuotaFixture()
    guard var snapshots = raw["quotaSnapshots"] as? [String: Any] else {
        throw URLError(.cannotDecodeContentData)
    }
    for key in ["premium_interactions", "chat", "completions"] {
        guard var snapshot = snapshots[key] as? [String: Any] else { continue }
        snapshot["entitlementRequests"] = 0
        snapshot["usedRequests"] = 0
        snapshot["remainingPercentage"] = 100
        snapshot["isUnlimitedEntitlement"] = true
        snapshots[key] = snapshot
    }
    raw["quotaSnapshots"] = snapshots

    let cli = CopilotQuotaParser.parse(raw)
    let billing = CopilotQuotaParser.parseBilling(
        ["usageItems": [Any]()],
        planLimit: 300,
        now: try #require(ISO8601DateFormatter().date(from: "2026-09-09T17:40:00Z"))
    )
    let result = GitHubCopilotUsageProvider.reconcile(cli: cli, billing: billing)

    #expect(cli.windows.isEmpty)
    #expect(billing.windows.isEmpty)
    #expect(result.windows.isEmpty)
    #expect(result.status != .live)
    #expect(result.windows.contains { $0.usedPercent == 0 } == false)
}
