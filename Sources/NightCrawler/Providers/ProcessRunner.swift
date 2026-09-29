import Darwin
import Foundation

enum ProcessRunner {
    struct RunResult {
        let output: Data
        let exitCode: Int32
    }

    static func run(
        command: String,
        arguments: [String] = [],
        timeout: TimeInterval? = 8
    ) async -> RunResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + arguments
        process.environment = ProcessInfo.processInfo.environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        let status: Int32 = await withCheckedContinuation { continuation in
            process.terminationHandler = { task in
                continuation.resume(returning: task.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: -1)
                return
            }
            if let timeout {
                Task {
                    try? await Task.sleep(for: .seconds(max(timeout, 0.05)))
                    if process.isRunning {
                        RestrictedProcess.terminateAndWait(process)
                    }
                }
            }
        }

        return RunResult(output: drain(pipe, timeout: 1), exitCode: status)
    }

    static func runString(command: String, arguments: [String] = []) async throws -> String {
        let result = await run(command: command, arguments: arguments)
        guard result.exitCode == 0 else {
            throw URLError(.badServerResponse)
        }
        guard let string = String(data: result.output, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }
        return string
    }

    static func drain(_ pipe: Pipe, timeout: TimeInterval = 0.2) -> Data {
        let handle = pipe.fileHandleForReading
        let flags = fcntl(handle.fileDescriptor, F_GETFL)
        if flags >= 0 { _ = fcntl(handle.fileDescriptor, F_SETFL, flags | O_NONBLOCK) }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 8_192)
        let deadline = Date().addingTimeInterval(max(timeout, 0.05))
        while Date() < deadline {
            let count = Darwin.read(handle.fileDescriptor, &buffer, buffer.count)
            if count > 0 {
                data.append(contentsOf: buffer.prefix(count))
                continue
            }
            if count == 0 { break }
            if errno == EAGAIN || errno == EWOULDBLOCK {
                Thread.sleep(forTimeInterval: 0.01)
                continue
            }
            break
        }
        return data
    }
}
