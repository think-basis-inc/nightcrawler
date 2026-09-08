import Darwin
import Foundation

struct BillingCommandResult: Sendable {
    let exitCode: Int32
    let stdout: Data
}

final class CopilotBillingClient: @unchecked Sendable {
    typealias Runner = @Sendable ([String], TimeInterval, Int) -> BillingCommandResult

    private let command: [String]
    private let planLimit: Int
    private let now: Date
    private let runner: Runner

    init(
        command: [String]? = nil,
        planLimit: Int,
        now: Date = Date(),
        runner: Runner? = nil
    ) {
        self.command = command ?? RestrictedProcess.resolveOnPath("gh").map { [$0] } ?? []
        self.planLimit = planLimit
        self.now = now
        self.runner = runner ?? Self.run
    }

    func query() async -> CopilotQuotaParser.Result {
        await Task.detached { [self] in querySynchronously() }.value
    }

    private func querySynchronously() -> CopilotQuotaParser.Result {
        guard let executable = command.first else {
            return .empty(error: "GitHub CLI is required for Copilot premium-request usage")
        }
        let loginResult = runner(
            [executable, "api", "user", "--jq", ".login"],
            8,
            1_024
        )
        guard loginResult.exitCode == 0,
              let login = String(data: loginResult.stdout, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              login.range(of: #"^[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})$"#, options: .regularExpression) != nil
        else {
            return .empty(status: .needsAuth, error: "Sign in to GitHub CLI to read Copilot usage")
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let parts = calendar.dateComponents([.year, .month], from: now)
        guard let year = parts.year, let month = parts.month else {
            return .empty(status: .error, error: "Could not determine the Copilot billing period")
        }
        let endpoint = "users/\(login)/settings/billing/premium_request/usage?year=\(year)&month=\(month)"
        let usageResult = runner([executable, "api", "--method", "GET", endpoint], 12, 1_048_576)
        guard usageResult.exitCode == 0 else {
            return .empty(
                status: .needsAuth,
                error: "GitHub CLI needs one-time Plan read access for Copilot usage"
            )
        }
        guard let raw = try? JSONSerialization.jsonObject(with: usageResult.stdout) else {
            return .empty(status: .error, error: "GitHub returned invalid Copilot billing metadata")
        }
        return CopilotQuotaParser.parseBilling(raw, planLimit: planLimit, now: now)
    }

    private static func run(_ command: [String], timeout: TimeInterval, maxBytes: Int) -> BillingCommandResult {
        guard let executable = command.first, RestrictedProcess.executableExists(executable) else {
            return BillingCommandResult(exitCode: -1, stdout: Data())
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = Array(command.dropFirst())
        process.environment = RestrictedProcess.environment()
        process.currentDirectoryURL = URL(fileURLWithPath: "/")
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
        } catch {
            return BillingCommandResult(exitCode: -1, stdout: Data())
        }

        let output = readBounded(
            pipe.fileHandleForReading,
            process: process,
            timeout: timeout,
            maxBytes: maxBytes
        )
        RestrictedProcess.terminateAndWait(process)
        return BillingCommandResult(exitCode: output == nil ? -1 : process.terminationStatus, stdout: output ?? Data())
    }

    private static func readBounded(
        _ handle: FileHandle,
        process: Process,
        timeout: TimeInterval,
        maxBytes: Int
    ) -> Data? {
        let flags = fcntl(handle.fileDescriptor, F_GETFL)
        if flags >= 0 { _ = fcntl(handle.fileDescriptor, F_SETFL, flags | O_NONBLOCK) }
        let deadline = Date().addingTimeInterval(timeout)
        var output = Data()
        var buffer = [UInt8](repeating: 0, count: 8_192)
        while Date() < deadline {
            let count = read(handle.fileDescriptor, &buffer, buffer.count)
            if count > 0 {
                output.append(contentsOf: buffer.prefix(count))
                if output.count > maxBytes { return nil }
                continue
            }
            if count == 0, !process.isRunning { return output }
            if count < 0, errno != EAGAIN, errno != EWOULDBLOCK { return nil }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return nil
    }
}

enum CopilotPlanSettings {
    static let key = "copilotPlanLimit"
    static let allowedLimits = [50, 300, 1_500]
    static let defaultLimit = 300

    static func current(defaults: UserDefaults = .standard) -> Int {
        let saved = defaults.integer(forKey: key)
        return allowedLimits.contains(saved) ? saved : defaultLimit
    }
}
