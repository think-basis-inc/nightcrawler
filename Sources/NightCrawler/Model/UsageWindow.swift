import Foundation

struct UsageWindow: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    let used: Int
    let limit: Int
    let usedPercent: Double
    let windowMinutes: Int?
    let resetsAt: Date?
    let observedAt: Date?

    init(
        id: String,
        label: String,
        used: Int,
        limit: Int,
        usedPercent: Double,
        windowMinutes: Int?,
        resetsAt: Date?,
        observedAt: Date? = nil
    ) {
        self.id = id
        self.label = label
        self.used = used
        self.limit = limit
        self.usedPercent = usedPercent
        self.windowMinutes = windowMinutes
        self.resetsAt = resetsAt
        self.observedAt = observedAt
    }

    func observed(at fallback: Date?) -> UsageWindow {
        guard observedAt == nil, let fallback else { return self }
        return UsageWindow(
            id: id,
            label: label,
            used: used,
            limit: limit,
            usedPercent: usedPercent,
            windowMinutes: windowMinutes,
            resetsAt: resetsAt,
            observedAt: fallback
        )
    }

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
