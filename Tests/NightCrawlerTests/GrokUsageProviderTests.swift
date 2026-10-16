import Foundation
import Testing
@testable import NightCrawler

private let start = ProviderHelpers.parseISO8601("2026-10-15T20:00:00Z")!

private final class Box<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value
    init(_ value: Value) { self.value = value }
    func get() -> Value { lock.withLock { value } }
    func update(_ body: (inout Value) -> Void) { lock.withLock { body(&value) } }
}

/// A Grok CLI session file in a scratch directory, plus the fakes a provider
/// reads it through: the billing endpoint accepts only the token "renewed".
private struct GrokFixture {
    let authPath: String
    let clock = Box(start)
    let refreshes = Box(0)
    let tokensSent = Box<[String]>([])

    init() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("grok-usage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        authPath = directory.appendingPathComponent("auth.json").path
    }

    func writeSession(token: String, expiresAt: Date, refreshToken: String? = "stored-refresh") throws {
        var entry: [String: Any] = [
            "key": token,
            "expires_at": ISO8601DateFormatter().string(from: expiresAt),
            "oidc_issuer": "https://auth.x.ai",
            "email": "nick@example.com",
        ]
        entry["refresh_token"] = refreshToken
        let data = try JSONSerialization.data(withJSONObject: ["https://auth.x.ai::client": entry])
        try data.write(to: URL(fileURLWithPath: authPath))
    }

    /// The CLI renewing its session: a new access token valid for six hours.
    func cliRenews() -> @Sendable () -> Void {
        { [self] in
            refreshes.update { $0 += 1 }
            try? writeSession(token: "renewed", expiresAt: clock.get().addingTimeInterval(6 * 3600))
        }
    }

    /// The CLI starting but leaving the session as it was.
    func cliChangesNothing() -> @Sendable () -> Void {
        { [self] in refreshes.update { $0 += 1 } }
    }

    func provider(refresher: @escaping @Sendable () -> Void) -> GrokUsageProvider {
        GrokUsageProvider(authPath: authPath, loader: { [self] request in
            let token = request.value(forHTTPHeaderField: "Authorization")?
                .replacingOccurrences(of: "Bearer ", with: "") ?? ""
            tokensSent.update { $0.append(token) }
            let ok = token == "renewed"
            let body = ok
                ? Data(#"{"config":{"creditUsagePercent":12,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","start":"2026-10-12T00:00:00Z","end":"2026-10-19T00:00:00Z"}}}"#.utf8)
                : Data()
            let response = HTTPURLResponse(url: request.url!, statusCode: ok ? 200 : 401,
                                           httpVersion: nil, headerFields: nil)!
            return (body, response)
        }, refresher: refresher, now: { [clock] in clock.get() })
    }
}

@Test
func expiredGrokSessionIsRenewedThroughTheCLIBeforeReadingUsage() async throws {
    let fixture = try GrokFixture()
    try fixture.writeSession(token: "expired", expiresAt: start.addingTimeInterval(-90 * 60))

    let reading = await fixture.provider(refresher: fixture.cliRenews()).read()

    #expect(reading.status == .live)
    #expect(reading.windows.first?.usedPercent == 12)
    #expect(fixture.refreshes.get() == 1)
    #expect(fixture.tokensSent.get() == ["renewed"], "an expired token is never sent to Grok")
}

@Test
func failedGrokRenewalsAskForSignInAndBackOffBeforeStartingTheCLIAgain() async throws {
    let fixture = try GrokFixture()
    try fixture.writeSession(token: "expired", expiresAt: start.addingTimeInterval(-60))
    let provider = fixture.provider(refresher: fixture.cliChangesNothing())

    #expect(await provider.read().status == .needsAuth)
    #expect(await provider.read().status == .needsAuth)
    #expect(fixture.refreshes.get() == 1, "a minute-by-minute poll must not relaunch the CLI each time")

    fixture.clock.update { $0 += 3 * 60 }
    #expect(await provider.read().status == .needsAuth)
    #expect(fixture.refreshes.get() == 2, "a wake without network retries within minutes")

    fixture.clock.update { $0 += 3 * 60 }
    _ = await provider.read()
    #expect(fixture.refreshes.get() == 2, "repeated failures wait longer each time")

    fixture.clock.update { $0 += 2 * 60 }
    _ = await provider.read()
    #expect(fixture.refreshes.get() == 3)
    #expect(fixture.tokensSent.get().isEmpty)
}

@Test
func grokRenewalAfterAFailureRecoversAsSoonAsTheCLISavesASession() async throws {
    let fixture = try GrokFixture()
    try fixture.writeSession(token: "expired", expiresAt: start.addingTimeInterval(-60))
    let offline = Box(true)
    let renew = fixture.cliRenews()
    let provider = fixture.provider(refresher: {
        if offline.get() { fixture.refreshes.update { $0 += 1 } } else { renew() }
    })

    #expect(await provider.read().status == .needsAuth)
    offline.update { $0 = false }
    fixture.clock.update { $0 += 2 * 60 }

    #expect(await provider.read().status == .live)
    #expect(fixture.refreshes.get() == 2)
}

@Test
func grokSessionRenewedOutsideTheAppClearsEarlierRenewalFailures() async throws {
    let fixture = try GrokFixture()
    try fixture.writeSession(token: "expired", expiresAt: start.addingTimeInterval(-60))
    let provider = fixture.provider(refresher: fixture.cliChangesNothing())
    for _ in 0..<4 {
        _ = await provider.read()
        fixture.clock.update { $0 += 3600 }
    }
    #expect(fixture.refreshes.get() == 4)

    // The user runs grok themselves; the app reads usage with that session.
    try fixture.writeSession(token: "renewed", expiresAt: fixture.clock.get().addingTimeInterval(6 * 3600))
    #expect(await provider.read().status == .live)

    try fixture.writeSession(token: "expired-again", expiresAt: fixture.clock.get().addingTimeInterval(-60))
    _ = await provider.read()
    fixture.clock.update { $0 += 2 * 60 }
    _ = await provider.read()
    #expect(fixture.refreshes.get() == 6, "a new session's first failure waits minutes, not the old hour")
}

@Test
func grokSessionWithoutARefreshTokenNeverStartsTheCLI() async throws {
    let fixture = try GrokFixture()
    try fixture.writeSession(token: "expired", expiresAt: start.addingTimeInterval(-60), refreshToken: nil)

    let reading = await fixture.provider(refresher: fixture.cliRenews()).read()

    #expect(reading.status == .needsAuth)
    #expect(fixture.refreshes.get() == 0)
}

@Test
func grokTokenRejectedBeforeItsExpiryIsRenewedAndRetriedOnce() async throws {
    let fixture = try GrokFixture()
    try fixture.writeSession(token: "revoked", expiresAt: start.addingTimeInterval(3600))

    let reading = await fixture.provider(refresher: fixture.cliRenews()).read()

    #expect(reading.status == .live)
    #expect(fixture.refreshes.get() == 1)
    #expect(fixture.tokensSent.get() == ["revoked", "renewed"])
}

@Test
func grokTokenStillRejectedAfterRenewalAsksForSignInWithoutLooping() async throws {
    let fixture = try GrokFixture()
    try fixture.writeSession(token: "revoked", expiresAt: start.addingTimeInterval(5 * 3600))

    let provider = fixture.provider(refresher: fixture.cliChangesNothing())

    #expect(await provider.read().status == .needsAuth)
    #expect(fixture.refreshes.get() == 1)
    #expect(fixture.tokensSent.get() == ["revoked"], "an unchanged token is not sent again")

    fixture.clock.update { $0 += 2 * 3600 }
    #expect(await provider.read().status == .needsAuth)
    #expect(fixture.refreshes.get() == 1, "a token Grok keeps rejecting must not relaunch the CLI all day")
}

@Test
func overlappingGrokReadsStartTheCLIOnlyOnce() async throws {
    let fixture = try GrokFixture()
    try fixture.writeSession(token: "expired", expiresAt: start.addingTimeInterval(-60))
    let renew = fixture.cliRenews()
    let provider = fixture.provider(refresher: {
        Thread.sleep(forTimeInterval: 0.2)
        renew()
    })

    async let first = provider.read()
    async let second = provider.read()
    _ = await (first, second)

    #expect(fixture.refreshes.get() == 1, "two CLI refreshes at once could race on the rotating refresh token")
}
