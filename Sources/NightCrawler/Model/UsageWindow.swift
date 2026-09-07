import Foundation

struct UsageWindow: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    let used: Int
    let limit: Int
    let usedPercent: Double
    let windowMinutes: Int?
    let resetsAt: Date?

    var fraction: Double {
        guard limit > 0 else { return 0 }
        return min(max(Double(used) / Double(limit), 0), 1)
    }

    var status: WindowStatus {
        switch fraction {
        case ..<0.7: return .ok
        case ..<0.9: return .warning
        default: return .critical
        }
    }
}

enum WindowStatus: Sendable {
    case ok
    case warning
    case critical
}
