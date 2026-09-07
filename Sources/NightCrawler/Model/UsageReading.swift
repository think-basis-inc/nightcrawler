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
        windows.first { $0.id == "weekly_all" } ?? headlineWindow
    }

    var innerRingWindow: UsageWindow? {
        guard providerId == "claude" else { return nil }
        return windows.first { $0.id == "weekly_scoped" || $0.id == "fable" }
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
