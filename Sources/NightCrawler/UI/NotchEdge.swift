import Foundation

enum NotchEdge: String, CaseIterable, Equatable {
    case right, left, top, bottom

    var isVertical: Bool { self == .right || self == .left }

    enum TooltipDirection: Equatable {
        case leading, trailing, up, down
    }

    var tooltipDirection: TooltipDirection {
        switch self {
        case .right: return .leading
        case .left: return .trailing
        case .top: return .down
        case .bottom: return .up
        }
    }
}
