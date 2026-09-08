import Foundation

enum HUDVisibilityGeometry {
    static func hiddenFrame(_ frame: CGRect, edge: NotchEdge, retraction: CGFloat) -> CGRect {
        switch edge {
        case .right:
            return frame.offsetBy(dx: retraction, dy: 0)
        case .left:
            return frame.offsetBy(dx: -retraction, dy: 0)
        case .top:
            return frame.offsetBy(dx: 0, dy: retraction)
        case .bottom:
            return frame.offsetBy(dx: 0, dy: -retraction)
        }
    }

    static func activationZone(in frame: CGRect, edge: NotchEdge, thickness: CGFloat) -> CGRect {
        switch edge {
        case .right:
            return CGRect(x: frame.maxX - thickness, y: frame.minY, width: thickness, height: frame.height)
        case .left:
            return CGRect(x: frame.minX, y: frame.minY, width: thickness, height: frame.height)
        case .top:
            return CGRect(x: frame.minX, y: frame.maxY - thickness, width: frame.width, height: thickness)
        case .bottom:
            return CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: thickness)
        }
    }

    static func shouldRetract(
        point: CGPoint,
        screenFrame: CGRect,
        edge: NotchEdge,
        revealedDepth: CGFloat
    ) -> Bool {
        !activationZone(
            in: screenFrame,
            edge: edge,
            thickness: max(revealedDepth, 0)
        ).contains(point)
    }
}
