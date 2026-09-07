import Foundation
import Testing
@testable import NightCrawler

private func stubCommand(_ mode: String) -> [String] {
    let stub = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/copilot-rpc-stub.py")
    return ["/usr/bin/python3", "-u", stub.path, "--rpc-server", mode]
}

@Test
func copilotMetadataOnlyRPCUsesSanitizedEnvironment() async {
    let client = CopilotRPCClient(
        command: stubCommand("normal"),
        timeout: 3,
        extraEnvironment: [
            "GH_TOKEN": "fixture-secret",
            "GITHUB_TOKEN": "fixture-secret",
            "COPILOT_GITHUB_TOKEN": "fixture-secret",
        ]
    )
    let result = await client.query()
    #expect(result.status == .live)
    #expect(result.authMode == "subscription")
    #expect(result.accountId != nil)
    #expect(result.accountId != "default")
    #expect(!(result.accountId?.contains("fixture-user") ?? false))
    #expect(client.lastEnvironment?.keys.contains("GH_TOKEN") != true)
    #expect(client.lastEnvironment?.keys.contains("GITHUB_TOKEN") != true)
    #expect(client.lastEnvironment?.keys.contains("COPILOT_GITHUB_TOKEN") != true)
    #expect(Set((client.lastEnvironment ?? [:]).keys).isSubset(of: ["HOME", "PATH", "LANG", "TMPDIR"]))
}

@Test
func copilotUnauthorizedStopsBeforeQuota() async {
    let result = await CopilotRPCClient(command: stubCommand("unauthorized"), timeout: 3).query()
    #expect(result.status == .needsAuth)
    #expect(result.windows.isEmpty)
}

@Test
func copilotRPCErrorIsSanitized() async {
    let result = await CopilotRPCClient(command: stubCommand("error"), timeout: 3).query()
    #expect(result.status == .error)
    #expect(!(result.error ?? "").contains("fixture-secret"))
}

@Test
func copilotOversizedResponseIsBounded() async {
    let result = await CopilotRPCClient(command: stubCommand("oversize"), timeout: 3).query()
    #expect(result.status == .error)
}

@Test
func copilotHungChildIsKilledAndReaped() async {
    let started = Date()
    let client = CopilotRPCClient(command: stubCommand("hang"), timeout: 0.25)
    let result = await client.query()
    #expect(result.error == "Copilot usage request timed out")
    #expect(Date().timeIntervalSince(started) < 2)
    #expect(client.lastChildWasReaped)
}

@Test
func copilotMissingCLIHasActionableStatus() async {
    let result = await CopilotRPCClient(command: ["/nonexistent/copilot-fixture"], timeout: 1).query()
    #expect(result.status == .needsAuth)
}
