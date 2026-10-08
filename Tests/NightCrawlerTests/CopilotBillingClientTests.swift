import Foundation
import Testing
@testable import NightCrawler

private final class BillingRunnerSpy: @unchecked Sendable {
    var calls: [[String]] = []
    var billingExitCode: Int32 = 0
    var internalUserBody: String?

    func run(_ command: [String], _: TimeInterval, _: Int) -> BillingCommandResult {
        calls.append(command)
        if command.contains("copilot_internal/user") {
            let body = internalUserBody ?? #"{"quota_snapshots":{}}"#
            return BillingCommandResult(exitCode: 0, stdout: Data(body.utf8))
        }
        if command.contains("user") {
            return BillingCommandResult(exitCode: 0, stdout: Data("fixture-user\n".utf8))
        }
        let body = #"{"usageItems":[{"product":"Copilot","grossQuantity":42}]}"#
        return BillingCommandResult(exitCode: billingExitCode, stdout: Data(body.utf8))
    }
}

@Test
func copilotBillingClientUsesGhWithoutReadingOrPassingAToken() async throws {
    let spy = BillingRunnerSpy()
    let now = try #require(ISO8601DateFormatter().date(from: "2026-09-07T12:00:00Z"))
    let client = CopilotBillingClient(
        command: ["/fixture/gh"],
        planLimit: 300,
        now: now,
        runner: spy.run
    )

    let result = await client.query()

    #expect(result.status == .live)
    #expect(abs((result.windows.first?.usedPercent ?? 0) - 14) < 0.000001)
    #expect(spy.calls.count == 2)
    #expect(spy.calls.flatMap { $0 }.allSatisfy { !$0.lowercased().contains("token") })
    #expect(spy.calls.last?.contains("users/fixture-user/settings/billing/premium_request/usage?year=2026&month=9") == true)
}

@Test
func copilotBillingClientExplainsMissingPlanReadScope() async throws {
    let spy = BillingRunnerSpy()
    spy.billingExitCode = 1
    let now = try #require(ISO8601DateFormatter().date(from: "2026-09-07T12:00:00Z"))
    let client = CopilotBillingClient(
        command: ["/fixture/gh"],
        planLimit: 300,
        now: now,
        runner: spy.run
    )

    let result = await client.query()

    #expect(result.status == .needsAuth)
    #expect(result.error?.contains("Plan read access") == true)
}

@Test
func copilotInternalUserClientUsesGhWithoutReadingOrPassingAToken() async throws {
    let spy = BillingRunnerSpy()
    spy.internalUserBody = """
    {"copilot_plan":"business","token_based_billing":true,"quota_reset_date":"2026-10-01","quota_snapshots":{"premium_interactions":{"credits_used":4909,"entitlement":0,"unlimited":true,"percent_remaining":100,"remaining":0,"token_based_billing":true}}}
    """
    let client = CopilotBillingClient(
        command: ["/fixture/gh"],
        planLimit: 300,
        runner: spy.run
    )

    let result = await client.queryInternalUser()
    let window = try #require(result.windows.first)

    #expect(result.status == .live)
    #expect(window.usedCount == 4909)
    #expect(window.includedLimit == 1_900)
    #expect(window.displaysPercent == true)
    #expect(spy.calls.count == 1)
    #expect(spy.calls[0].contains("copilot_internal/user"))
    #expect(spy.calls.flatMap { $0 }.allSatisfy { !$0.lowercased().contains("token") })
    #expect(spy.calls.flatMap { $0 }.contains { $0.contains("premium_request") } == false)
}

@Test
func missingBillingScopeDoesNotClaimTheAuthenticatedCopilotServiceIsDown() {
    let cli = CopilotQuotaParser.Result.empty(
        status: .unknown,
        error: "Copilot did not report a finite subscription allowance",
        accountId: "sanitized-account",
        authMode: "subscription"
    )
    let billing = CopilotQuotaParser.Result.empty(
        status: .needsAuth,
        error: "GitHub CLI needs one-time Plan read access for Copilot usage"
    )

    let result = GitHubCopilotUsageProvider.reconcile(cli: cli, billing: billing)

    #expect(result.status == .unknown)
    #expect(result.accountId == "sanitized-account")
    #expect(result.authMode == "subscription")
    #expect(result.error?.contains("Plan read access") == true)
}
