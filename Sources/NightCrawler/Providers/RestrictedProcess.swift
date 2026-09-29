import Darwin
import Foundation

enum RestrictedProcess {
    static let allowedKeys: Set<String> = [
        "HOME", "PATH", "LANG", "TMPDIR", "USER", "LOGNAME", "SHELL",
        "__CF_USER_TEXT_ENCODING",
    ]

    static func environment() -> [String: String] {
        environment(from: ProcessInfo.processInfo.environment)
    }

    static func environment(from env: [String: String]) -> [String: String] {
        var restricted: [String: String] = [:]
        for key in allowedKeys {
            if let value = env[key] {
                restricted[key] = value
            }
        }
        let user = restricted["USER"] ?? restricted["LOGNAME"] ?? NSUserName()
        restricted["USER"] = user
        restricted["LOGNAME"] = restricted["LOGNAME"] ?? user
        restricted["SHELL"] = restricted["SHELL"] ?? "/bin/zsh"
        return restricted
    }

    static func executableExists(_ path: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: path)
    }

    static func terminateAndWait(_ process: Process, grace: TimeInterval = 0.25) {
        let pid = process.processIdentifier
        if process.isRunning {
            process.terminate()
            let deadline = Date().addingTimeInterval(max(grace, 0))
            while process.isRunning, Date() < deadline {
                Thread.sleep(forTimeInterval: 0.01)
            }
            if process.isRunning {
                _ = Darwin.kill(pid, SIGKILL)
                let killDeadline = Date().addingTimeInterval(0.2)
                while process.isRunning, Date() < killDeadline {
                    Thread.sleep(forTimeInterval: 0.01)
                }
            }
        }
        if pid > 0 {
            var status: Int32 = 0
            _ = waitpid(pid, &status, WNOHANG)
        }
    }

    static func resolveOnPath(
        _ name: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> String? {
        guard !name.isEmpty, !name.contains("/") else { return nil }
        let pathDirectories = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        let standardDirectories = [
            homeDirectory.appendingPathComponent(".local/bin").path,
            homeDirectory.appendingPathComponent(".cargo/bin").path,
            "/opt/homebrew/bin",
            "/usr/local/bin",
        ]
        var seen: Set<String> = []
        for directory in pathDirectories + standardDirectories where seen.insert(directory).inserted {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent(name).path
            if executableExists(candidate) { return candidate }
        }
        return nil
    }
}
