import AppKit
import Foundation

/// How a signed-out provider gets signed back in. NightCrawler never handles
/// credentials itself: it hands the user to the tool's own login flow, which
/// writes the credentials NightCrawler already reads.
enum ProviderSignIn: Equatable, Sendable {
    /// Runs the tool's login command in Terminal so interactive prompts work.
    case terminal(command: String, arguments: [String])
    /// Opens the desktop app that owns the session.
    case app(bundleIdentifier: String, name: String)

    static func method(for providerId: String) -> ProviderSignIn? {
        switch providerId {
        case "codex": return .terminal(command: "codex", arguments: ["login"])
        case "claude": return .terminal(command: "claude", arguments: ["auth", "login"])
        case "grok": return .terminal(command: "grok", arguments: ["login"])
        case "opencode": return .terminal(command: "opencode", arguments: ["auth", "login"])
        case "copilot": return .terminal(command: "copilot", arguments: ["login"])
        case "devin": return .terminal(command: "devin", arguments: ["auth", "login"])
        case "cubic": return .terminal(command: "gh", arguments: ["auth", "login"])
        case "cursor", "grokbot": return .app(bundleIdentifier: "com.todesktop.230313mzl4w4u92", name: "Cursor")
        case "antigravity": return .app(bundleIdentifier: "com.google.antigravity", name: "Antigravity")
        default: return nil
        }
    }

    /// A missing CLI or app cannot sign anyone in; its provider keeps the
    /// ordinary card instead of a sign-in that would fail.
    static func isInstalled(_ method: ProviderSignIn) -> Bool {
        switch method {
        case .terminal(let command, _):
            return RestrictedProcess.resolveOnPath(command) != nil
        case .app(let bundleIdentifier, _):
            return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
        }
    }

    /// One line telling the user where the sign-in will happen.
    var hint: String {
        switch self {
        case .terminal(let command, let arguments):
            return "Opens Terminal to run \(([command] + arguments).joined(separator: " "))"
        case .app(_, let name):
            return "Opens \(name) to sign in"
        }
    }

    /// The `.command` script Terminal runs. Login shell so the user's PATH and
    /// tool setup apply; the window stays open so the outcome stays readable.
    static func script(executable: String, arguments: [String]) -> String {
        let line = ([executable] + arguments).map(shellQuoted).joined(separator: " ")
        return """
        #!/bin/zsh -l
        \(line)
        rc=$?
        echo
        if [ $rc -eq 0 ]; then echo "Signed in. You can close this window."; else echo "Sign-in exited with status $rc."; fi

        """
    }

    static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

@MainActor
struct ProviderSignInLauncher {
    var scriptDirectory: URL = FileManager.default.temporaryDirectory
        .appendingPathComponent("NightCrawlerSignIn", isDirectory: true)
    var resolveExecutable: (String) -> String? = { RestrictedProcess.resolveOnPath($0) }
    var openFile: (URL) -> Bool = { NSWorkspace.shared.open($0) }
    var openApp: (String) -> Bool = { bundleIdentifier in
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return false
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        return true
    }

    @discardableResult
    func launch(_ method: ProviderSignIn, providerId: String) -> Bool {
        switch method {
        case .app(let bundleIdentifier, _):
            return openApp(bundleIdentifier)
        case .terminal(let command, let arguments):
            guard let url = try? writeScript(command: command, arguments: arguments, providerId: providerId) else {
                return false
            }
            return openFile(url)
        }
    }

    func writeScript(command: String, arguments: [String], providerId: String) throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: scriptDirectory, withIntermediateDirectories: true)
        let url = scriptDirectory.appendingPathComponent("sign-in-\(providerId).command")
        // A GUI app's PATH rarely includes ~/.local/bin; resolve here and let
        // the login shell find it only when NightCrawler could not.
        let executable = resolveExecutable(command) ?? command
        try ProviderSignIn.script(executable: executable, arguments: arguments)
            .write(to: url, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }
}
