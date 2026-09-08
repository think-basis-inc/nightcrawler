import Foundation

/// Stores only sanitized, successful quota snapshots so the local routing
/// endpoint has honest stale data while fresh providers are still loading.
enum PersistedReadingCache {
    static let key = "lastGoodUsageReadings"
    static let maxAge: TimeInterval = 24 * 60 * 60

    static func load(
        defaults: UserDefaults,
        knownProviderIds: Set<String>,
        now: Date = Date()
    ) -> [UsageReading] {
        guard let data = defaults.data(forKey: key),
              let rows = try? JSONDecoder().decode([Row].self, from: data)
        else { return [] }
        return rows.compactMap { row in
            guard knownProviderIds.contains(row.providerId),
                  now.timeIntervalSince(row.observedAt) <= maxAge,
                  now.timeIntervalSince(row.observedAt) >= -120
            else { return nil }
            let windows = row.windows.filter { window in
                let observedAt = window.observedAt ?? row.observedAt
                return (window.resetsAt == nil || window.resetsAt! > now)
                    && now.timeIntervalSince(observedAt) <= maxAge
                    && now.timeIntervalSince(observedAt) >= -120
            }.map { window in
                UsageWindow(
                    id: window.id,
                    label: window.label,
                    used: Int(window.usedPercent * 100),
                    limit: 10_000,
                    usedPercent: window.usedPercent,
                    windowMinutes: window.windowMinutes,
                    resetsAt: window.resetsAt,
                    observedAt: window.observedAt ?? row.observedAt
                )
            }
            guard !windows.isEmpty else { return nil }
            return UsageReading(
                providerId: row.providerId,
                label: row.label,
                accountId: nil,
                authMode: "unknown",
                source: "last_good_cache",
                windows: windows,
                status: .live,
                observedAt: row.observedAt,
                error: nil
            )
        }
    }

    static func save(_ readings: [UsageReading], defaults: UserDefaults) {
        let rows = readings.compactMap { reading -> Row? in
            guard reading.status == .live,
                  let observedAt = reading.observedAt,
                  !reading.windows.isEmpty
            else { return nil }
            return Row(
                providerId: reading.providerId,
                label: reading.label,
                observedAt: observedAt,
                windows: reading.windows.map {
                    Window(
                        id: $0.id,
                        label: $0.label,
                        usedPercent: $0.usedPercent,
                        windowMinutes: $0.windowMinutes,
                        resetsAt: $0.resetsAt,
                        observedAt: $0.observedAt ?? reading.observedAt
                    )
                }
            )
        }
        guard let data = try? JSONEncoder().encode(rows) else { return }
        defaults.set(data, forKey: key)
    }

    private struct Row: Codable {
        let providerId: String
        let label: String
        let observedAt: Date
        let windows: [Window]
    }

    private struct Window: Codable {
        let id: String
        let label: String
        let usedPercent: Double
        let windowMinutes: Int?
        let resetsAt: Date?
        let observedAt: Date?
    }
}
