import Foundation

/// Reads Dino's already-sanitized provider snapshots. No credential, browser
/// session, or account identifier is present in the resulting reading.
enum DinoUsageCache {
    static let maxBytes = 1_048_576

    static func reading(from data: Data, providerId: String, fallbackLabel: String) -> UsageReading? {
        guard data.count <= maxBytes,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let row = root[providerId] as? [String: Any],
              row["provider"] as? String == providerId
        else { return nil }

        let windows = (row["windows"] as? [[String: Any]] ?? []).prefix(32).compactMap { item -> UsageWindow? in
            guard let usedPercent = number(item["used_percent"]), usedPercent <= 1_000 else { return nil }
            let used = integer(item["used_count"]) ?? Int(usedPercent.rounded())
            let limit = integer(item["limit_count"]) ?? 100
            guard limit > 0 else { return nil }
            return UsageWindow(
                id: boundedString(item["id"], fallback: "window"),
                label: boundedString(item["label"], fallback: "Allowance"),
                used: used,
                limit: limit,
                usedPercent: usedPercent,
                windowMinutes: integer(item["window_minutes"]),
                resetsAt: resetDate(item)
            )
        }

        let state = row["state"] as? String
        let error = boundedOptionalString(row["error"])
        let status: UsageReading.ReadingStatus
        switch state {
        case "live", "stale":
            status = windows.isEmpty ? .unknown : .live
        case "needs_auth":
            status = .needsAuth
        case "error":
            status = .error(error ?? "Usage unavailable")
        default:
            status = .unknown
        }

        return UsageReading(
            providerId: providerId,
            label: fallbackLabel,
            accountId: nil,
            authMode: boundedString(row["auth_mode"], fallback: "unknown"),
            source: boundedString(row["source"], fallback: "dino_sanitized_cache"),
            windows: windows,
            status: status,
            observedAt: ProviderHelpers.parseISO8601(row["observed_at"] as? String),
            error: error
        )
    }

    private static func resetDate(_ item: [String: Any]) -> Date? {
        if let epoch = number(item["resets_at"]), epoch <= 253_402_300_799 {
            return Date(timeIntervalSince1970: epoch)
        }
        guard let day = item["resets_on"] as? String else { return nil }
        return ProviderHelpers.parseISO8601(day + "T00:00:00Z")
    }

    private static func number(_ value: Any?) -> Double? {
        if value is Bool { return nil }
        guard let number = value as? NSNumber else { return nil }
        let value = number.doubleValue
        return value.isFinite && value >= 0 ? value : nil
    }

    private static func integer(_ value: Any?) -> Int? {
        guard let value = number(value), value <= Double(Int.max), value.rounded() == value else { return nil }
        return Int(value)
    }

    private static func boundedString(_ value: Any?, fallback: String) -> String {
        guard let value = value as? String, !value.isEmpty, value.count <= 120 else { return fallback }
        return value
    }

    private static func boundedOptionalString(_ value: Any?) -> String? {
        guard let value = value as? String, !value.isEmpty else { return nil }
        return String(value.prefix(200))
    }
}

struct DinoCacheUsageProvider: UsageProvider {
    let id: String
    let label: String
    private let candidateURLs: [URL]

    init(id: String, label: String, candidateURLs: [URL]? = nil) {
        self.id = id
        self.label = label
        if let candidateURLs {
            self.candidateURLs = candidateURLs
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            self.candidateURLs = [".dino-beta", ".dino"].map {
                home.appendingPathComponent($0).appendingPathComponent("subscriptions-\(id).json")
            }
        }
    }

    var isAvailable: Bool {
        candidateURLs.contains { FileManager.default.fileExists(atPath: $0.path) }
    }

    func read() async -> UsageReading {
        let candidates = candidateURLs.compactMap { url -> UsageReading? in
            guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
            defer { try? handle.close() }
            guard let data = try? handle.read(upToCount: DinoUsageCache.maxBytes + 1) else { return nil }
            return DinoUsageCache.reading(from: data, providerId: id, fallbackLabel: label)
        }
        if let newest = candidates.max(by: { ($0.observedAt ?? .distantPast) < ($1.observedAt ?? .distantPast) }) {
            return newest
        }
        return UsageReading(
            providerId: id,
            label: label,
            accountId: nil,
            authMode: "unknown",
            source: "dino_sanitized_cache",
            windows: [],
            status: .unknown,
            observedAt: nil,
            error: "No usage snapshot is available yet"
        )
    }
}
