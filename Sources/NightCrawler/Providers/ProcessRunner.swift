import Foundation

enum ProcessRunner {
    struct RunResult {
        let output: Data
        let exitCode: Int32
    }

    static func run(command: String, arguments: [String] = []) async -> RunResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + arguments
        process.environment = ProcessInfo.processInfo.environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        return await withCheckedContinuation { continuation in
            process.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: RunResult(output: data, exitCode: process.terminationStatus))
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: RunResult(output: Data(), exitCode: -1))
            }
        }
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
}
