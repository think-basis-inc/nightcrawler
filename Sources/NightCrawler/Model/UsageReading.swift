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

    enum ReadingStatus: Equatable, Sendable {
        case live
        case needsAuth
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
