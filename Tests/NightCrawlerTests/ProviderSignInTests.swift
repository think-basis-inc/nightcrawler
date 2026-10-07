import Foundation
import Security
import Testing
@testable import NightCrawler

private func reading(
    _ providerId: String,
    status: UsageReading.ReadingStatus,
    source: String = "provider"
) -> UsageReading {
    UsageReading(
        providerId: providerId,
        label: providerId.capitalized,
        accountId: nil,
        authMode: "unknown",
        source: source,
        windows: [],
        status: status,
        observedAt: nil,
        error: status == .needsAuth ? "Sign-in expired" : nil
    )
}

@Test
func clickingASignedOutIconStartsThatToolsOwnLogin() {
    // Each tool's documented login entry point (its CLI help or desktop app).
    let expected: [String: ProviderSignIn] = [
        "codex": .terminal(command: "codex", arguments: ["login"]),
        "claude": .terminal(command: "claude", arguments: ["auth", "login"]),
        "grok": .terminal(command: "grok", arguments: ["login"]),
        "opencode": .terminal(command: "opencode", arguments: ["auth", "login"]),
        "copilot": .terminal(command: "copilot", arguments: ["login"]),
        "devin": .terminal(command: "devin", arguments: ["auth", "login"]),
        "cubic": .terminal(command: "gh", arguments: ["auth", "login"]),
        "cursor": .app(bundleIdentifier: "com.todesktop.230313mzl4w4u92", name: "Cursor"),
        "grokbot": .app(bundleIdentifier: "com.todesktop.230313mzl4w4u92", name: "Cursor"),
        "antigravity": .app(bundleIdentifier: "com.google.antigravity", name: "Antigravity"),
    ]
    for (providerId, method) in expected {
        #expect(HUDIconAction.resolve(for: reading(providerId, status: .needsAuth), isInstalled: { _ in true }) == .signIn(method),
                "\(providerId) should start its own sign-in")
    }
}

@Test
func iconsThatAreNotSignedOutKeepOpeningTheirCard() {
    #expect(HUDIconAction.resolve(for: reading("codex", status: .live)) == .toggleDetail)
    #expect(HUDIconAction.resolve(for: reading("codex", status: .error("ChatGPT returned 500"))) == .toggleDetail)
    #expect(HUDIconAction.resolve(for: reading("codex", status: .unknown)) == .toggleDetail)
    #expect(
        HUDIconAction.resolve(for: reading("codex", status: .needsAuth, source: UsageReading.pendingSource)) == .toggleDetail,
        "a placeholder that has not asked the provider yet is not a sign-out"
    )
    #expect(
        HUDIconAction.resolve(for: reading("zcode", status: .needsAuth)) == .toggleDetail,
        "an API-key provider has no sign-in flow to start"
    )
}

@Test
func aToolThatIsNotInstalledIsNotOfferedASignIn() {
    // Copilot and Cubic report needsAuth when their CLI is missing; a login
    // command that cannot run must not replace the card.
    #expect(HUDIconAction.resolve(for: reading("copilot", status: .needsAuth), isInstalled: { _ in false }) == .toggleDetail)
    #expect(DetailPanelView.signInMethod(for: reading("cubic", status: .needsAuth), isInstalled: { _ in false }) == nil)
}

@Test
func signedOutCardOffersSignInOnlyWhenAFlowExists() {
    let installed: @Sendable (ProviderSignIn) -> Bool = { _ in true }
    #expect(DetailPanelView.signInMethod(for: reading("grok", status: .needsAuth), isInstalled: installed) != nil)
    #expect(DetailPanelView.signInMethod(for: reading("grok", status: .live), isInstalled: installed) == nil)
    #expect(DetailPanelView.signInMethod(for: reading("zcode", status: .needsAuth), isInstalled: installed) == nil)
    #expect(HUDLayout.signInCardHeight <= HUDLayout.defaultMaxCardHeight,
            "the sign-in card must fit inside the panel reserved for cards")
}

@MainActor
@Test
func terminalSignInRunsTheResolvedLoginCommand() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("NightCrawlerSignInTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let toolDirectory = root.appendingPathComponent("tool dir with 'quote'", isDirectory: true)
    try FileManager.default.createDirectory(at: toolDirectory, withIntermediateDirectories: true)
    let record = root.appendingPathComponent("args.txt")
    let stub = toolDirectory.appendingPathComponent("codex")
    try "#!/bin/sh\nprintf '%s\\n' \"$@\" > '\(record.path)'\n".write(to: stub, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stub.path)

    var opened: [URL] = []
    var launcher = ProviderSignInLauncher()
    launcher.scriptDirectory = root.appendingPathComponent("scripts", isDirectory: true)
    launcher.resolveExecutable = { $0 == "codex" ? stub.path : nil }
    launcher.openFile = { opened.append($0); return true }

    #expect(launcher.launch(.terminal(command: "codex", arguments: ["login"]), providerId: "codex"))
    let script = try #require(opened.first)
    #expect(script.pathExtension == "command", "Terminal opens .command files")
    #expect(FileManager.default.isExecutableFile(atPath: script.path))

    // Run it the way Terminal would, isolated from the user's zsh startup files.
    let process = Process()
    process.executableURL = script
    let zdotdir = root.appendingPathComponent("zdotdir", isDirectory: true)
    try FileManager.default.createDirectory(at: zdotdir, withIntermediateDirectories: true)
    process.environment = ["HOME": root.path, "ZDOTDIR": zdotdir.path, "PATH": "/usr/bin:/bin"]
    let output = Pipe()
    process.standardOutput = output
    try process.run()
    process.waitUntilExit()

    #expect(process.terminationStatus == 0)
    #expect(try String(contentsOf: record, encoding: .utf8) == "login\n")
    let printed = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    #expect(printed.contains("Signed in. You can close this window."))
}

@MainActor
@Test
func appSignInOpensTheOwningApp() {
    var openedBundle: String?
    var launcher = ProviderSignInLauncher()
    launcher.openApp = { openedBundle = $0; return true }
    launcher.openFile = { _ in Issue.record("an app sign-in must not open Terminal"); return false }

    #expect(launcher.launch(.app(bundleIdentifier: "com.google.antigravity", name: "Antigravity"), providerId: "antigravity"))
    #expect(openedBundle == "com.google.antigravity")
}

private final class SignInSequenceProvider: UsageProvider, @unchecked Sendable {
    let id: String
    let label = "Codex CLI"
    private let lock = NSLock()
    private var signedOutReadsLeft: Int
    private var reads = 0
    private let signedOutSource: String

    init(id: String = "codex", signedOutReads: Int, signedOutSource: String = "provider") {
        self.id = id
        signedOutReadsLeft = signedOutReads
        self.signedOutSource = signedOutSource
    }

    var isAvailable: Bool { true }

    var readCount: Int { lock.withLock { reads } }

    func read() async -> UsageReading {
        let signedOut: Bool = lock.withLock {
            reads += 1
            guard signedOutReadsLeft > 0 else { return false }
            signedOutReadsLeft -= 1
            return true
        }
        if signedOut { return reading(id, status: .needsAuth, source: signedOutSource) }
        return UsageReading(
            providerId: id, label: label, accountId: "acct", authMode: "subscription",
            source: "codex_cli_usage",
            windows: [UsageWindow(id: "primary", label: "Weekly limit", used: 1900, limit: 10000,
                                  usedPercent: 19, windowMinutes: 10080, resetsAt: nil)],
            status: .live, observedAt: Date(), error: nil
        )
    }
}

@MainActor
@Test
func signInWatchRestoresTheRingOnceTheToolSavesCredentials() async throws {
    let suiteName = "NightCrawlerTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let provider = SignInSequenceProvider(signedOutReads: 2)
    let store = UsageStore(providers: [provider], defaults: defaults)

    store.watchSignIn(providerId: "codex", interval: .milliseconds(10), attempts: 20)

    let deadline = Date().addingTimeInterval(20)
    while store.readings.first(where: { $0.providerId == "codex" })?.status != .live, Date() < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(store.readings.first { $0.providerId == "codex" }?.status == .live)

    let readsWhenLive = provider.readCount
    try await Task.sleep(for: .milliseconds(150))
    #expect(provider.readCount == readsWhenLive, "the watch stops once the provider is signed in")
}

@MainActor
@Test
func signInWatchGivesUpAfterItsAttempts() async throws {
    let suiteName = "NightCrawlerTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let provider = SignInSequenceProvider(signedOutReads: .max)
    let store = UsageStore(providers: [provider], defaults: defaults)

    store.watchSignIn(providerId: "codex", interval: .milliseconds(5), attempts: 3)
    let deadline = Date().addingTimeInterval(20)
    while provider.readCount < 3, Date() < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
    try await Task.sleep(for: .milliseconds(150))

    #expect(provider.readCount == 3, "the watch stops after its attempts")
    #expect(store.readings.first { $0.providerId == "codex" }?.isSignedOut == true)
}

@MainActor
@Test
func antigravitySignInThatTakesAWhileStillRestoresTheRing() async throws {
    // Expired credentials are an ordinary sign-out, not a keychain denial:
    // the watch must keep going until the user finishes in Antigravity.
    let suiteName = "NightCrawlerTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let provider = SignInSequenceProvider(id: "antigravity", signedOutReads: 3)
    let store = UsageStore(providers: [provider], defaults: defaults)

    store.watchSignIn(providerId: "antigravity", interval: .milliseconds(5), attempts: 10)
    let deadline = Date().addingTimeInterval(20)
    while store.readings.first(where: { $0.providerId == "antigravity" })?.status != .live, Date() < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }

    #expect(store.readings.first { $0.providerId == "antigravity" }?.status == .live)
}

@MainActor
@Test
func signInWatchDoesNotRepeatADeniedKeychainPrompt() async throws {
    let suiteName = "NightCrawlerTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let provider = SignInSequenceProvider(
        id: "antigravity", signedOutReads: .max, signedOutSource: UsageReading.keychainDeniedSource
    )
    let store = UsageStore(providers: [provider], defaults: defaults)

    store.watchSignIn(providerId: "antigravity", interval: .milliseconds(5), attempts: 10)
    let deadline = Date().addingTimeInterval(20)
    while provider.readCount < 1, Date() < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
    try await Task.sleep(for: .milliseconds(150))

    #expect(provider.readCount == 1)
}

@Test
func aDeniedKeychainPromptAsksForARetryNotALogin() {
    let denied = reading("antigravity", status: .needsAuth, source: UsageReading.keychainDeniedSource)
    #expect(!denied.isSignedOut)
    #expect(HUDIconAction.resolve(for: denied, isInstalled: { _ in true }) == .toggleDetail)
}

@Test
func keychainDenialIsToldApartFromAMissingItem() {
    #expect(Keychain.isDenial(errSecUserCanceled))
    #expect(Keychain.isDenial(errSecAuthFailed))
    #expect(Keychain.isDenial(errSecInteractionNotAllowed))
    #expect(!Keychain.isDenial(errSecItemNotFound))
}

@MainActor
@Test
func aDeniedKeychainPromptBehindStaleCachedUsageStillAsksForARetry() async throws {
    let suiteName = "NightCrawlerTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let provider = SignInSequenceProvider(
        id: "antigravity", signedOutReads: .max, signedOutSource: UsageReading.keychainDeniedSource
    )
    let store = UsageStore(providers: [provider], defaults: defaults)
    let staleAt = Date().addingTimeInterval(-3600)
    store.readings = [UsageReading(
        providerId: "antigravity", label: "Antigravity", accountId: nil, authMode: "subscription",
        source: "last_good_cache",
        windows: [UsageWindow(id: "daily", label: "Daily", used: 40, limit: 100,
                              usedPercent: 40, windowMinutes: 1440, resetsAt: nil)],
        status: .live, observedAt: staleAt, error: nil
    )]

    store.watchSignIn(providerId: "antigravity", interval: .milliseconds(5), attempts: 10)
    let deadline = Date().addingTimeInterval(20)
    while provider.readCount < 1, Date() < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
    try await Task.sleep(for: .milliseconds(150))

    let stored = try #require(store.readings.first { $0.providerId == "antigravity" })
    #expect(stored.status == .needsAuth)
    #expect(HUDIconAction.resolve(for: stored, isInstalled: { _ in true }) == .toggleDetail,
            "a click must retry the keychain, not open Antigravity")
    #expect(provider.readCount == 1, "the watch must not raise the denied prompt again")
}
