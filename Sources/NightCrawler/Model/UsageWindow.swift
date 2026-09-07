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
        min(max(usedPercent / 100, 0), 1)
    }

    var status: WindowStatus {
        switch fraction {
        case ..<0.50: return .ok
        case ..<0.70: return .warning
        default: return .critical
        }
    }
}

enum WindowStatus: Sendable {
    case ok
    case warning
    case critical
}
