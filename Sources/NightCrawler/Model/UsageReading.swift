import Foundation

struct UsageReading: Identifiable, Equatable {
    let id = UUID()
    let providerId: String
    let label: String
    let percentUsed: Double
    let used: Int
    let limit: Int
    let windowName: String
    let resetsAt: Date?
    let status: ReadingStatus

    var fraction: Double {
        guard limit > 0 else { return 0 }
        return min(max(Double(used) / Double(limit), 0), 1)
    }

    enum ReadingStatus: Equatable {
        case ok
        case warning
        case critical
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
