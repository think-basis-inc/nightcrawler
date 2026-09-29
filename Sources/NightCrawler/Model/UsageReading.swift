import Foundation

struct UsageReading: Identifiable, Equatable, Sendable {
    let id = UUID()
    let providerId: String
    let label: String
    let accountId: String?
    let authMode: String
    let source: String
    let windows: [UsageWindow]
    let status: ReadingStatus
    let observedAt: Date?
    let error: String?

    var headlineWindow: UsageWindow? {
        windows.max { $0.fraction < $1.fraction }
    }

    var outerRingWindow: UsageWindow? {
        if providerId == "devin" {
            return windows.first { $0.id == "weekly" }
        }
        if providerId == "cursor" {
            return windows.first { $0.id == "included" }
                ?? windows.first { $0.id == "auto" || $0.id == "cursor_models" }
        }
        if providerId == "claude" {
            return windows.first { $0.id == "weekly_all" }
        }
        return windows.first { $0.id == "weekly_all" || $0.id == "included" || $0.id == "cursor_models" } ?? headlineWindow
    }

    var innerRingWindow: UsageWindow? {
        switch providerId {
        case "claude":
            return windows.first { $0.id == "weekly_scoped" || $0.id == "fable" }
        case "cursor":
            return windows.first { $0.id == "api" || $0.id == "other_models" }
        case "devin":
            return windows.first { $0.id == "daily" }
        default:
            return nil
        }
    }

    var thirdRingWindow: UsageWindow? {
        nil
    }

    var displayWindows: [UsageWindow] {
        func rank(_ id: String) -> Int {
            switch providerId {
            case "claude":
                switch id {
                case "weekly_all": return 0
                case "weekly_scoped", "fable": return 1
                case "session": return 2
                default: return 3
                }
            case "cursor":
                switch id {
                case "included", "auto", "cursor_models": return 0
                case "api", "other_models": return 1
                default: return 2
                }
            default:
                return 0
            }
        }
        guard providerId == "claude" || providerId == "cursor" else { return windows }
        return windows.sorted { rank($0.id) < rank($1.id) }
    }

    func isFreshlyObserved(now: Date = Date()) -> Bool {
        guard status == .live, !windows.isEmpty else { return false }
        if providerId == "cubic" {
            return windows.contains { window in
                window.resetsAt.map { $0 > now } ?? true
            }
        }
        // Claude's local cache only updates while Claude Code runs, so an
        // unreset window stays current. Polled providers must keep proving it.
        if providerId == "claude", windows.contains(where: { window in
            window.resetsAt.map { $0 > now } ?? false
        }) {
            return true
        }
        guard let observedAt else { return false }
        let age = now.timeIntervalSince(observedAt)
        return age <= CapacitySnapshot.liveFreshnessInterval && age >= -120
    }

    enum ReadingStatus: Equatable, Sendable {
        case live
        case needsAuth
        case unknown
        case error(String)
    }
}

extension UsageReading.ReadingStatus {
    var isError: Bool {
        switch self {
        case .error, .needsAuth: return true
        default: return false
        }
    }
}
