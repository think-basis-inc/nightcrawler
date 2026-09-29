import Darwin
import Foundation

enum ClaudeCLIUsageParser {
    static func windows(from data: Data, now: Date = Date()) -> [UsageWindow] {
        guard var text = String(data: data, encoding: .utf8) else { return [] }
        text = text.replacingOccurrences(
            of: #"\u{001B}\[[0-?]*[ -/]*[@-~]"#,
            with: "",
            options: .regularExpression
        )
        let lines = text.split(whereSeparator: \Character.isNewline).map(String.init)
        let definitions: [(label: String, id: String, title: String, minutes: Int)] = [
            ("Current session", "session", "Current session", 300),
            ("Current week (all models)", "weekly_all", "All models", 10_080),
            ("Current week (Fable)", "fable", "Fable", 10_080),
        ]
        return definitions.compactMap { definition in
            guard let labelIndex = lines.lastIndex(where: { $0.contains(definition.label) }) else { return nil }
            let end = min(lines.endIndex, labelIndex + 6)
            let block = lines[(labelIndex + 1)..<end]
            guard let usedLine = block.first(where: { $0.localizedCaseInsensitiveContains("used") }),
                  let percent = firstPercent(in: usedLine)
            else { return nil }
            return UsageWindow(
                id: definition.id,
                label: definition.title,
                used: Int(percent * 100),
                limit: 10_000,
                usedPercent: percent,
                windowMinutes: definition.minutes,
                resetsAt: resetInstant(from: block, now: now)
            )
        }
    }

    static func resetInstant(from lines: ArraySlice<String>, now: Date) -> Date? {
        for line in lines {
            if let date = parseResetLine(line, now: now) { return date }
        }
        return nil
    }

    static func parseResetLine(_ line: String, now: Date) -> Date? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.localizedCaseInsensitiveContains("reset") else { return nil }

        var zone = TimeZone.current
        var core = trimmed
        if let open = trimmed.lastIndex(of: "("),
           let close = trimmed.lastIndex(of: ")"),
           open < close {
            let identifier = String(trimmed[trimmed.index(after: open)..<close])
            if let parsed = TimeZone(identifier: identifier) {
                zone = parsed
            }
            core = String(trimmed[..<open]).trimmingCharacters(in: .whitespaces)
        }
        core = core.replacingOccurrences(of: "Resets", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "Reset", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespaces)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let formats = [
            "MMM d 'at' h:mma",
            "MMM d 'at' ha",
            "MMM d h:mma",
            "h:mma",
            "ha",
            "h:mm a",
            "h a",
        ]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.calendar = calendar
        formatter.defaultDate = now

        let compact = core
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ".", with: "")
            .lowercased()
        let spaced = core
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "  ", with: " ")

        for candidate in [core, spaced, compact] {
            for format in formats {
                formatter.dateFormat = format
                if let parsed = formatter.date(from: candidate) {
                    return datedReset(parsed, now: now, calendar: calendar, format: format)
                }
            }
        }
        return nil
    }

    private static func datedReset(_ parsed: Date, now: Date, calendar: Calendar, format: String) -> Date {
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: parsed)
        let nowParts = calendar.dateComponents([.year, .month, .day], from: now)
        if !format.contains("MMM") {
            components.year = nowParts.year
            components.month = nowParts.month
            components.day = nowParts.day
        } else if components.year == nil {
            components.year = nowParts.year
        }
        guard var date = calendar.date(from: components) else { return parsed }
        if !format.contains("MMM"), date <= now {
            date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        } else if format.contains("MMM"), date.addingTimeInterval(12 * 60 * 60) < now {
            date = calendar.date(byAdding: .year, value: 1, to: date) ?? date
        }
        return date
    }

    private static func firstPercent(in line: String) -> Double? {
        guard let range = line.range(of: #"[0-9]+(?:\.[0-9]+)?%"#, options: .regularExpression),
              let value = Double(line[range].dropLast()),
              value.isFinite, (0...1_000).contains(value)
        else { return nil }
        return value
    }
}

/// Runs Claude Code's local `/usage` command in screen-reader mode. The slash
/// command reads subscription metadata but never starts a model turn.
final class ClaudeCLIUsageClient: @unchecked Sendable {
    static let maxOutputBytes = 262_144

    private let command: [String]
    private let timeout: TimeInterval
    private let workingDirectory: URL

    init(
        command: [String]? = nil,
        timeout: TimeInterval = 15,
        workingDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
    ) {
        self.command = command
            ?? RestrictedProcess.resolveOnPath("claude").map { [$0, "--safe-mode", "--ax-screen-reader"] }
            ?? []
        self.timeout = timeout
        self.workingDirectory = workingDirectory
    }

    func readWindows() async -> [UsageWindow] {
        await Task.detached { [self] in run() }.value
    }

    private func run() -> [UsageWindow] {
        guard let executable = command.first,
              RestrictedProcess.executableExists(executable),
              RestrictedProcess.executableExists("/usr/bin/script")
        else { return [] }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/script")
        process.arguments = ["-q", "/dev/null", executable] + command.dropFirst()
        var environment = RestrictedProcess.environment()
        environment["TERM"] = "xterm-256color"
        environment["COLUMNS"] = "100"
        environment["LINES"] = "60"
        process.environment = environment
        process.currentDirectoryURL = workingDirectory
        process.standardError = FileHandle.nullDevice

        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        do {
            try process.run()
        } catch {
            return []
        }

        let outputHandle = output.fileHandleForReading
        let flags = fcntl(outputHandle.fileDescriptor, F_GETFL)
        if flags >= 0 { _ = fcntl(outputHandle.fileDescriptor, F_SETFL, flags | O_NONBLOCK) }
        let deadline = Date().addingTimeInterval(timeout)
        var bytes = Data()
        var sentUsage = false
        var buffer = [UInt8](repeating: 0, count: 8_192)

        var weeklyAllSeenAt: Date? = nil

        while Date() < deadline, bytes.count <= Self.maxOutputBytes {
            let count = Darwin.read(outputHandle.fileDescriptor, &buffer, buffer.count)
            if count > 0 {
                bytes.append(contentsOf: buffer.prefix(count))
            } else if count < 0, errno != EAGAIN, errno != EWOULDBLOCK {
                break
            }

            let rawText = String(data: bytes, encoding: .utf8) ?? ""
            let text = rawText.replacingOccurrences(
                of: #"\u{001B}\[[0-?]*[ -/]*[@-~]"#,
                with: "",
                options: .regularExpression
            )
            if !sentUsage, text.contains("auto mode") || text.contains("you:") {
                _ = Darwin.signal(SIGPIPE, SIG_IGN)
                try? input.fileHandleForWriting.write(contentsOf: Data("/usage\r".utf8))
                sentUsage = true
            }
            let windows = ClaudeCLIUsageParser.windows(from: bytes)
            if windows.contains(where: { $0.id == "weekly_all" }) {
                if windows.contains(where: { $0.id == "fable" }) {
                    stop(process, input: input.fileHandleForWriting)
                    return windows
                }
                if weeklyAllSeenAt == nil {
                    weeklyAllSeenAt = Date()
                }
                if text.contains("Per-model breakdown unavailable")
                    || text.contains("Usage credits")
                    || text.contains("r to retry")
                    || text.contains("/usage-credits") {
                    stop(process, input: input.fileHandleForWriting)
                    return windows
                }
                if let seen = weeklyAllSeenAt, Date().timeIntervalSince(seen) >= 0.8 {
                    stop(process, input: input.fileHandleForWriting)
                    return windows
                }
            }
            if !process.isRunning { break }
            Thread.sleep(forTimeInterval: 0.02)
        }

        let windows = ClaudeCLIUsageParser.windows(from: bytes)
        stop(process, input: input.fileHandleForWriting)
        return windows
    }

    private func stop(_ process: Process, input: FileHandle) {
        _ = Darwin.signal(SIGPIPE, SIG_IGN)
        if process.isRunning {
            try? input.write(contentsOf: Data([0x1B, 0x03, 0x03]))
        }
        try? input.close()
        RestrictedProcess.terminateAndWait(process)
    }
}
