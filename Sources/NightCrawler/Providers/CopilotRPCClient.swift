import Darwin
import Foundation

final class CopilotRPCClient: @unchecked Sendable {
    static let defaultArguments = [
        "--headless", "--stdio", "--no-auto-update", "--log-level", "none",
        "--disable-builtin-mcps", "--no-custom-instructions",
    ]
    static let maxBodyBytes = 65_536

    var command: [String]
    var timeout: TimeInterval
    var extraEnvironment: [String: String]

    private(set) var lastEnvironment: [String: String]?
    private(set) var lastChildWasReaped = false

    init(command: [String], timeout: TimeInterval, extraEnvironment: [String: String] = [:]) {
        self.command = command
        self.timeout = timeout
        self.extraEnvironment = extraEnvironment
    }

    static func defaultCommand() -> [String]? {
        guard let binary = RestrictedProcess.resolveOnPath("copilot") else { return nil }
        return [binary] + defaultArguments
    }

    func query() async -> CopilotQuotaParser.Result {
        await Task.detached { [self] in
            self.runQuery()
        }.value
    }

    private func runQuery() -> CopilotQuotaParser.Result {
        lastChildWasReaped = false
        let env = RestrictedProcess.environment()
        lastEnvironment = env
        guard let executable = command.first, RestrictedProcess.executableExists(executable) else {
            return .empty(status: .needsAuth, error: "Install and sign in to GitHub Copilot CLI to read usage")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = Array(command.dropFirst())
        process.environment = env
        process.currentDirectoryURL = URL(fileURLWithPath: "/")
        process.standardError = FileHandle.nullDevice

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe

        do {
            try process.run()
        } catch {
            reap(process)
            return .empty(status: .needsAuth, error: "Install and sign in to GitHub Copilot CLI to read usage")
        }

        let connection = QuotaConnection(
            process: process,
            stdin: stdinPipe.fileHandleForWriting,
            stdout: stdoutPipe.fileHandleForReading,
            deadline: Date().addingTimeInterval(timeout)
        )
        defer {
            connection.close()
            reap(process)
        }

        do {
            let handshake = try connection.request("ping")
            let version = intValue(handshake["protocolVersion"])
            guard let version, version >= 2 else {
                return .empty(status: .error, error: "Copilot account quota is unavailable from this CLI")
            }
            let auth = try connection.request("auth.getStatus")
            guard auth["isAuthenticated"] as? Bool == true,
                  auth["authType"] as? String == "user",
                  auth["host"] as? String == "https://github.com"
            else {
                return .empty(status: .needsAuth, error: "Sign in to GitHub Copilot CLI to read account usage")
            }
            var row = CopilotQuotaParser.parse(try connection.request("account.getQuota"))
            if let login = auth["login"] as? String, (1...256).contains(login.count) {
                row.accountId = ProviderHelpers.sha256Prefix("github.com/" + login.lowercased())
            }
            if !row.windows.isEmpty {
                row.authMode = "subscription"
            }
            return row
        } catch is TimeoutError {
            return .empty(status: .error, error: "Copilot usage request timed out")
        } catch {
            return .empty(status: .error, error: "Copilot account quota is unavailable from this CLI")
        }
    }

    private func reap(_ process: Process) {
        if process.isRunning {
            process.terminate()
        }
        process.waitUntilExit()
        lastChildWasReaped = true
    }

    private func intValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
            return number.intValue
        }
        if let int = value as? Int { return int }
        return nil
    }
}

private struct TimeoutError: Error {}
private struct RPCError: Error {}

private final class QuotaConnection {
    private let process: Process
    private let stdin: FileHandle
    private let stdout: FileHandle
    private let deadline: Date
    private var buffer = Data()
    private var received = 0
    private var sequence = 0

    init(process: Process, stdin: FileHandle, stdout: FileHandle, deadline: Date) {
        self.process = process
        self.stdin = stdin
        self.stdout = stdout
        self.deadline = deadline
        let flags = fcntl(stdout.fileDescriptor, F_GETFL)
        if flags >= 0 {
            _ = fcntl(stdout.fileDescriptor, F_SETFL, flags | O_NONBLOCK)
        }
    }

    func request(_ method: String) throws -> [String: Any] {
        guard ["ping", "auth.getStatus", "account.getQuota"].contains(method) else {
            throw RPCError()
        }
        sequence += 1
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": sequence,
            "method": method,
            "params": [String: Any](),
        ]
        let message = try JSONSerialization.data(withJSONObject: payload)
        var frame = Data("Content-Length: \(message.count)\r\n\r\n".utf8)
        frame.append(message)
        stdin.write(frame)

        while Date() < deadline {
            if let headerRange = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let header = buffer.subdata(in: buffer.startIndex..<headerRange.lowerBound)
                guard let headerText = String(data: header, encoding: .utf8),
                      headerText.hasPrefix("Content-Length: "),
                      let length = Int(headerText.dropFirst("Content-Length: ".count).trimmingCharacters(in: .whitespacesAndNewlines)),
                      length > 0, length <= CopilotRPCClient.maxBodyBytes
                else { throw RPCError() }
                let bodyStart = headerRange.upperBound
                if buffer.count - bodyStart >= length {
                    let body = buffer.subdata(in: bodyStart..<(bodyStart + length))
                    buffer.removeSubrange(buffer.startIndex..<(bodyStart + length))
                    guard let object = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
                        throw RPCError()
                    }
                    if intValue(object["id"]) != sequence { continue }
                    if object["error"] != nil { throw RPCError() }
                    guard let result = object["result"] as? [String: Any] else { throw RPCError() }
                    return result
                }
            }
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { throw TimeoutError() }
            let chunk = try readChunk(timeout: remaining)
            received += chunk.count
            if chunk.isEmpty || received > CopilotRPCClient.maxBodyBytes { throw RPCError() }
            buffer.append(chunk)
        }
        throw TimeoutError()
    }

    func close() {
        try? stdin.close()
        try? stdout.close()
        if process.isRunning {
            process.terminate()
        }
    }

    private func readChunk(timeout: TimeInterval) throws -> Data {
        let end = Date().addingTimeInterval(timeout)
        var buffer = [UInt8](repeating: 0, count: 8192)
        while Date() < end {
            let n = read(stdout.fileDescriptor, &buffer, buffer.count)
            if n > 0 {
                return Data(buffer.prefix(n))
            }
            if n == 0 { return Data() }
            if errno != EAGAIN && errno != EWOULDBLOCK { throw RPCError() }
            if !process.isRunning { return Data() }
            Thread.sleep(forTimeInterval: 0.01)
        }
        throw TimeoutError()
    }

    private func intValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
            return number.intValue
        }
        if let int = value as? Int { return int }
        return nil
    }
}
