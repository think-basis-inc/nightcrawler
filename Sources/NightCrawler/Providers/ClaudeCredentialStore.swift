import Foundation

struct SecurityInvocation: Equatable, Sendable {
    var executable: String
    var arguments: [String]
    var environment: [String: String]
    var stdinClosed: Bool
    var stderrDiscarded: Bool
    var timeout: TimeInterval
}

struct SecurityRunResult: Sendable {
    var exitCode: Int32
    var stdout: Data
}

actor ClaudeCredentialStore {
    static let shared = ClaudeCredentialStore()
    static let maxBytes = 65_536
    static let service = "Claude Code-credentials"

    typealias Runner = @Sendable (SecurityInvocation) -> SecurityRunResult

    private let runner: Runner
    private var cache: Cache?

    private enum Cache {
        case token(String)
        case refused
    }

    init(runner: Runner? = nil) {
        self.runner = runner ?? ClaudeCredentialStore.defaultRunner
    }

    func read() async -> String? {
        switch cache {
        case .token(let token):
            return token
        case .refused:
            return nil
        case .none:
            break
        }

        let invocation = SecurityInvocation(
            executable: "/usr/bin/security",
            arguments: ["find-generic-password", "-s", Self.service, "-w"],
            environment: RestrictedProcess.environment(),
            stdinClosed: true,
            stderrDiscarded: true,
            timeout: 8
        )
        let result = runner(invocation)
        guard result.exitCode == 0, result.stdout.count <= Self.maxBytes,
              let token = parseToken(result.stdout)
        else {
            cache = .refused
            return nil
        }
        cache = .token(token)
        return token
    }

    func allowRetry() {
        cache = nil
    }

    func noteSourceChange() {
        cache = nil
    }

    private func parseToken(_ data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              token.range(of: #"^[A-Za-z0-9._~-]{1,16384}$"#, options: .regularExpression) != nil,
              let expires = number(oauth["expiresAt"]), expires / 1000 > Date().timeIntervalSince1970,
              let subscription = oauth["subscriptionType"] as? String, !subscription.isEmpty
        else { return nil }
        return token
    }

    private func number(_ value: Any?) -> Double? {
        if value is Bool { return nil }
        if let double = value as? Double, double.isFinite, double >= 0 { return double }
        if let int = value as? Int, int >= 0 { return Double(int) }
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            let double = number.doubleValue
            return double.isFinite && double >= 0 ? double : nil
        }
        return nil
    }

    nonisolated static func defaultRunner(_ invocation: SecurityInvocation) -> SecurityRunResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: invocation.executable)
        process.arguments = invocation.arguments
        process.environment = invocation.environment
        process.currentDirectoryURL = URL(fileURLWithPath: "/")
        if invocation.stdinClosed {
            process.standardInput = FileHandle.nullDevice
        }
        if invocation.stderrDiscarded {
            process.standardError = FileHandle.nullDevice
        }
        let pipe = Pipe()
        process.standardOutput = pipe
        do {
            try process.run()
        } catch {
            return SecurityRunResult(exitCode: -1, stdout: Data())
        }
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            process.waitUntilExit()
            group.leave()
        }
        let timedOut = group.wait(timeout: .now() + invocation.timeout) == .timedOut
        if timedOut {
            process.terminate()
            process.waitUntilExit()
            return SecurityRunResult(exitCode: -1, stdout: Data())
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return SecurityRunResult(exitCode: process.terminationStatus, stdout: data)
    }
}
