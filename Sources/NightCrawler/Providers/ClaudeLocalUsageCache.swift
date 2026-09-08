import Foundation

/// Reads the usage snapshot Claude Code already writes to `~/.claude.json`.
/// That file is updated by a real Claude Code session and does not require
/// spawning `claude /usage` or calling the OAuth usage API.
struct ClaudeLocalUsageCache: Sendable {
    static let shared = ClaudeLocalUsageCache()
    static let maxAge: TimeInterval = 24 * 60 * 60

    typealias Reader = @Sendable (URL) -> Data?

    private let fileURL: URL
    private let reader: Reader

    init(
        fileURL: URL = ClaudeLocalUsageCache.defaultFileURL,
        reader: Reader? = nil
    ) {
        self.fileURL = fileURL
        self.reader = reader ?? ClaudeLocalUsageCache.defaultReader
    }

    func windows(now: Date = Date()) -> [UsageWindow] {
        guard let data = reader(fileURL) else { return [] }
        return Self.windows(from: data, now: now)
    }

    static func windows(from data: Data, now: Date = Date()) -> [UsageWindow] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cache = root["cachedUsageUtilization"] as? [String: Any],
              let utilization = cache["utilization"] as? [String: Any]
        else { return [] }

        let fetchedAt: Date
        if let millis = number(cache["fetchedAtMs"]) {
            fetchedAt = Date(timeIntervalSince1970: millis / 1000)
        } else {
            fetchedAt = now
        }
        guard now.timeIntervalSince(fetchedAt) <= maxAge,
              now.timeIntervalSince(fetchedAt) >= -120
        else { return [] }

        var collected: [String: UsageWindow] = [:]
        if let limits = utilization["limits"] as? [[String: Any]] {
            for limit in limits {
                guard let kind = limit["kind"] as? String,
                      let percent = number(limit["percent"])
                else { continue }
                collected[kind] = UsageWindow(
                    id: kind,
                    label: ClaudeUsageLabels.label(for: kind),
                    used: Int(percent * 100),
                    limit: 10_000,
                    usedPercent: percent,
                    windowMinutes: windowMinutes(for: kind),
                    resetsAt: ProviderHelpers.parseISO8601(limit["resets_at"] as? String),
                    observedAt: fetchedAt
                )
            }
        }
        merge(
            utilization["five_hour"] as? [String: Any],
            id: "session",
            label: "Current session",
            minutes: 300,
            into: &collected,
            observedAt: fetchedAt
        )
        merge(
            utilization["seven_day"] as? [String: Any],
            id: "weekly_all",
            label: "All models",
            minutes: 10_080,
            into: &collected,
            observedAt: fetchedAt
        )
        return collected.values.sorted { rank($0.id) < rank($1.id) }
    }

    private static func merge(
        _ raw: [String: Any]?,
        id: String,
        label: String,
        minutes: Int,
        into collected: inout [String: UsageWindow],
        observedAt: Date
    ) {
        guard collected[id] == nil,
              let raw,
              let percent = number(raw["utilization"])
        else { return }
        collected[id] = UsageWindow(
            id: id,
            label: label,
            used: Int(percent * 100),
            limit: 10_000,
            usedPercent: percent,
            windowMinutes: minutes,
            resetsAt: ProviderHelpers.parseISO8601(raw["resets_at"] as? String),
            observedAt: observedAt
        )
    }

    private static func number(_ value: Any?) -> Double? {
        if value is Bool { return nil }
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            let double = number.doubleValue
            return double.isFinite && double >= 0 ? double : nil
        }
        return nil
    }

    private static func windowMinutes(for kind: String) -> Int? {
        kind == "session" ? 300 : (kind.hasPrefix("weekly_") ? 10_080 : nil)
    }

    private static func rank(_ id: String) -> Int {
        switch id {
        case "session": return 0
        case "weekly_all": return 1
        default: return 2
        }
    }

    private static let defaultFileURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude.json")

    nonisolated private static func defaultReader(_ url: URL) -> Data? {
        try? Data(contentsOf: url, options: [.mappedIfSafe])
    }
}
