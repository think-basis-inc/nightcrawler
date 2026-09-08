import Foundation
import Testing
@testable import NightCrawler

private let sampleToken = "test-subscription-token"

private func credentialJSON(
    token: String = sampleToken,
    expiresAt: Double = (Date().timeIntervalSince1970 + 3600) * 1000
) -> Data {
    let payload: [String: Any] = [
        "claudeAiOauth": [
            "accessToken": token,
            "expiresAt": expiresAt,
            "subscriptionType": "max",
        ]
    ]
    return try! JSONSerialization.data(withJSONObject: payload)
}

private final class ReaderSpy: @unchecked Sendable {
    var reads = 0
    var data: Data? = credentialJSON()

    func read(_: URL) -> Data? {
        reads += 1
        return data
    }
}

@Test
func claudeUsesItsExistingCredentialFileWithoutAKeychainPrompt() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let source = try String(
        contentsOf: root.appendingPathComponent("Sources/NightCrawler/Providers/ClaudeCredentialStore.swift"),
        encoding: .utf8
    )

    #expect(source.contains(".claude/.credentials.json"))
    #expect(!source.contains("/usr/bin/security"))
}

@Test
func claudeCredentialReaderReturnsValidatedFileToken() async {
    let spy = ReaderSpy()
    let store = ClaudeCredentialStore(fileURL: URL(fileURLWithPath: "/fixture"), reader: spy.read)
    #expect(await store.read() == sampleToken)
    #expect(spy.reads == 1)
}

@Test
func claudeRepeatedPollsDoNotRereadCredentials() async {
    let spy = ReaderSpy()
    let store = ClaudeCredentialStore(fileURL: URL(fileURLWithPath: "/fixture"), reader: spy.read)
    #expect(await store.read() == sampleToken)
    #expect(await store.read() == sampleToken)
    #expect(spy.reads == 1)
}

@Test
func claudeMissingCredentialFileIsNotRereadUntilExplicitRetry() async {
    let spy = ReaderSpy()
    spy.data = nil
    let store = ClaudeCredentialStore(fileURL: URL(fileURLWithPath: "/fixture"), reader: spy.read)
    #expect(await store.read() == nil)
    #expect(await store.read() == nil)
    #expect(spy.reads == 1)
    await store.allowRetry()
    #expect(await store.read() == nil)
    #expect(spy.reads == 2)
}

@Test
func claudeExpiredCredentialIsRejected() async {
    let spy = ReaderSpy()
    spy.data = credentialJSON(expiresAt: (Date().timeIntervalSince1970 - 1) * 1000)
    let store = ClaudeCredentialStore(fileURL: URL(fileURLWithPath: "/fixture"), reader: spy.read)
    #expect(await store.read() == nil)
}

@MainActor
@Test
func scheduledPollInvalidatesTheCachedClaudeCredential() async {
    let suiteName = "NightCrawlerTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let spy = ReaderSpy()
    let credentials = ClaudeCredentialStore(fileURL: URL(fileURLWithPath: "/fixture"), reader: spy.read)
    #expect(await credentials.read() == sampleToken)
    spy.data = credentialJSON(token: "rotated-subscription-token")
    let usage = UsageStore(providers: [], defaults: defaults, claudeCredentials: credentials)

    await usage.poll()

    #expect(await credentials.read() == "rotated-subscription-token")
    #expect(spy.reads == 2)
}
