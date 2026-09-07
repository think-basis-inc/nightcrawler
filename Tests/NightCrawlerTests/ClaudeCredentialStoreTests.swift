import Foundation
import Testing
@testable import NightCrawler

private let sampleToken = "test-subscription-token"

private func credentialJSON(token: String = sampleToken, expiresAt: Double = (Date().timeIntervalSince1970 + 3600) * 1000) -> Data {
    let payload: [String: Any] = [
        "claudeAiOauth": [
            "accessToken": token,
            "expiresAt": expiresAt,
            "subscriptionType": "max",
        ]
    ]
    return try! JSONSerialization.data(withJSONObject: payload)
}

private final class SpyRunner: @unchecked Sendable {
    var invocations: [SecurityInvocation] = []
    var result = SecurityRunResult(exitCode: 0, stdout: credentialJSON())

    func run(_ invocation: SecurityInvocation) -> SecurityRunResult {
        invocations.append(invocation)
        return result
    }
}

@Test
func claudeCredentialReaderNeverPutsTokenInArgv() async throws {
    let spy = SpyRunner()
    let store = ClaudeCredentialStore(runner: spy.run)
    let token = await store.read()
    #expect(token == sampleToken)
    let invocation = try #require(spy.invocations.first)
    #expect(invocation.executable == "/usr/bin/security")
    #expect(invocation.arguments == ["find-generic-password", "-s", "Claude Code-credentials", "-w"])
    #expect(!invocation.arguments.contains(sampleToken))
    #expect(!invocation.executable.contains(sampleToken))
    #expect(invocation.stdinClosed)
    #expect(invocation.stderrDiscarded)
    #expect(invocation.timeout <= 8)
    #expect(Set(invocation.environment.keys).isSubset(of: ["HOME", "PATH", "LANG", "TMPDIR"]))
}

@Test
func claudeRepeatedPollsDoNotRereadCredentials() async {
    let spy = SpyRunner()
    let store = ClaudeCredentialStore(runner: spy.run)
    #expect(await store.read() == sampleToken)
    #expect(await store.read() == sampleToken)
    #expect(spy.invocations.count == 1)
}

@Test
func claudeRecordedRefusalDoesNotRerunCredentialRead() async {
    let spy = SpyRunner()
    spy.result = SecurityRunResult(exitCode: 1, stdout: Data())
    let store = ClaudeCredentialStore(runner: spy.run)
    #expect(await store.read() == nil)
    #expect(await store.read() == nil)
    #expect(spy.invocations.count == 1)
}

@Test
func claudeExplicitRetryRereadsCredentials() async {
    let spy = SpyRunner()
    let store = ClaudeCredentialStore(runner: spy.run)
    #expect(await store.read() == sampleToken)
    await store.allowRetry()
    #expect(await store.read() == sampleToken)
    #expect(spy.invocations.count == 2)
}

@Test
func claudeSourceChangeRereadsCredentials() async {
    let spy = SpyRunner()
    let store = ClaudeCredentialStore(runner: spy.run)
    #expect(await store.read() == sampleToken)
    await store.noteSourceChange()
    #expect(await store.read() == sampleToken)
    #expect(spy.invocations.count == 2)
}
