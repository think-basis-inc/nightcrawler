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
