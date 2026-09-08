import Foundation

/// Reads the latest quota snapshot Codex already wrote to its local session
/// log. This is a read-only fallback when a separately stored OAuth token has
/// been revoked while an active Codex session is still receiving quota data.
struct CodexSessionUsageReader: Sendable {
    static let maxTailBytes: UInt64 = 524_288

    let rootURL: URL
    let now: Date

    init(
        rootURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions"),
        now: Date = Date()
    ) {
        self.rootURL = rootURL
        self.now = now
    }

    func read() -> UsageReading? {
        for fileURL in recentFiles() {
            guard let data = Self.readTail(of: fileURL) else { continue }
            for rawLine in data.split(separator: 0x0A).reversed() {
                guard let line = String(data: Data(rawLine), encoding: .utf8),
                      let reading = Self.parse(line: line)
                else { continue }
                return reading
            }
        }
        return nil
    }

    static func parse(line: String) -> UsageReading? {
        guard let data = line.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = root["payload"] as? [String: Any],
              let limits = payload["rate_limits"] as? [String: Any]
        else { return nil }

        let candidates: [(String, Any?)] = [
            ("primary", limits["primary"]),
            ("secondary", limits["secondary"]),
        ]
        let windows = candidates.compactMap { id, value -> UsageWindow? in
            guard let window = value as? [String: Any],
                  let percent = finiteNumber(window["used_percent"]),
                  (0...1_000).contains(percent)
            else { return nil }
            let minutes = finiteNumber(window["window_minutes"]).map(Int.init)
            let resetsAt = finiteNumber(window["resets_at"]).map(Date.init(timeIntervalSince1970:))
            return UsageWindow(
                id: id,
                label: label(for: minutes),
                used: Int(percent * 100),
                limit: 10_000,
                usedPercent: percent,
                windowMinutes: minutes,
                resetsAt: resetsAt
            )
        }
        guard !windows.isEmpty else { return nil }

        return UsageReading(
            providerId: "codex",
            label: "Codex CLI",
            accountId: nil,
            authMode: (limits["plan_type"] as? String).map { _ in "subscription" } ?? "unknown",
            source: "codex_session_rate_limits",
            windows: windows,
            status: .live,
            observedAt: ProviderHelpers.parseISO8601(root["timestamp"] as? String),
            error: nil
        )
    }

    private func recentFiles() -> [URL] {
        var files: [URL] = []
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        for dayOffset in 0...2 {
            guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: now) else { continue }
            let components = calendar.dateComponents([.year, .month, .day], from: day)
            guard let year = components.year, let month = components.month, let day = components.day else { continue }
            let directory = rootURL
                .appendingPathComponent(String(format: "%04d", year))
                .appendingPathComponent(String(format: "%02d", month))
                .appendingPathComponent(String(format: "%02d", day))
            let contents = (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            files.append(contentsOf: contents.filter { $0.pathExtension == "jsonl" })
        }
        return files.sorted {
            let lhs = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhs = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhs > rhs
        }.prefix(20).map { $0 }
    }

    private static func readTail(of url: URL) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd() else { return nil }
        let start = end > maxTailBytes ? end - maxTailBytes : 0
        do {
            try handle.seek(toOffset: start)
            var data = try handle.readToEnd() ?? Data()
            if start > 0, let newline = data.firstIndex(of: 0x0A) {
                data.removeSubrange(data.startIndex...newline)
            }
            return data
        } catch {
            return nil
        }
    }

    private static func finiteNumber(_ value: Any?) -> Double? {
        guard !(value is Bool), let number = value as? NSNumber else { return nil }
        let result = number.doubleValue
        return result.isFinite ? result : nil
    }

    private static func label(for minutes: Int?) -> String {
        switch minutes {
        case 300: return "Current session"
        case 10_080: return "Weekly limit"
        case 43_200: return "Monthly limit"
        case .some(let value): return "\(value)m limit"
        case .none: return "Usage limit"
        }
    }
}
