import Foundation
import Testing
@testable import NightCrawler

@Test
func guiLaunchedAppFindsUserLocalExecutablesWithoutATerminalPath() throws {
    let temporary = FileManager.default.temporaryDirectory
        .appendingPathComponent("NightCrawlerTests-\(UUID().uuidString)")
    let executable = temporary.appendingPathComponent(".local/bin/claude")
    try FileManager.default.createDirectory(
        at: executable.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: temporary) }
    try Data("#!/bin/sh\n".utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

    let resolved = RestrictedProcess.resolveOnPath(
        "claude",
        environment: ["PATH": "/usr/bin:/bin"],
        homeDirectory: temporary
    )

    #expect(resolved == executable.path)
}

@Test
func sanitizedChildEnvironmentKeepsMacOSIdentityButDropsProviderSecrets() {
    let environment = RestrictedProcess.environment(from: [
        "HOME": "/Users/example",
        "PATH": "/usr/bin:/bin",
        "LANG": "en_CA.UTF-8",
        "TMPDIR": "/tmp/example",
        "USER": "example",
        "LOGNAME": "example",
        "SHELL": "/bin/zsh",
        "__CF_USER_TEXT_ENCODING": "fixture-encoding",
        "ANTHROPIC_API_KEY": "must-not-pass",
        "GH_TOKEN": "must-not-pass",
    ])

    #expect(environment["USER"] == "example")
    #expect(environment["LOGNAME"] == "example")
    #expect(environment["SHELL"] == "/bin/zsh")
    #expect(environment["__CF_USER_TEXT_ENCODING"] == "fixture-encoding")
    #expect(environment["ANTHROPIC_API_KEY"] == nil)
    #expect(environment["GH_TOKEN"] == nil)
}

@Test
func terminateAndWaitEscalatesWhenAChildIgnoresTermination() throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", "trap '' TERM; while :; do :; done"]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    let started = Date()

    RestrictedProcess.terminateAndWait(process, grace: 0.05)

    #expect(!process.isRunning)
    #expect(Date().timeIntervalSince(started) < 1)
}
