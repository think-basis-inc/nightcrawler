import Foundation

struct NotchPlacement {
    let edge: NotchEdge
    let panelSize: CGSize

    func point(along: CGFloat, across: CGFloat) -> CGPoint {
        switch edge {
        case .right: return CGPoint(x: panelSize.width - across, y: along)
        case .left: return CGPoint(x: across, y: along)
        case .top: return CGPoint(x: along, y: across)
        case .bottom: return CGPoint(x: along, y: panelSize.height - across)
        }
    }

    func rect(along: CGFloat, across: CGFloat, length: CGFloat, depth: CGFloat) -> CGRect {
        switch edge {
        case .right:
            return CGRect(x: panelSize.width - across - depth, y: along, width: depth, height: length)
        case .left:
            return CGRect(x: across, y: along, width: depth, height: length)
        case .top:
            return CGRect(x: along, y: across, width: length, height: depth)
        case .bottom:
            return CGRect(x: along, y: panelSize.height - across - depth, width: length, height: depth)
        }
    }

    static func panelSize(edge: NotchEdge, length: CGFloat, depth: CGFloat) -> CGSize {
        edge.isVertical
            ? CGSize(width: depth, height: length)
            : CGSize(width: length, height: depth)
    }
}
