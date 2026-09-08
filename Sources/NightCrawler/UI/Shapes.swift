import SwiftUI

/// Pill welded to a screen edge with inverse rounded flares, canonical for the
/// right edge then transformed. Ported from Codenotch `SideNotchShape`.
struct SideNotchShape: Shape {
    var edge: NotchEdge = .right
    var curlRadius: CGFloat = HUDLayout.curlRadius
    var cornerRadius: CGFloat = HUDLayout.cornerRadius

    func path(in rect: CGRect) -> Path {
        let depth = edge.isVertical ? rect.width : rect.height
        let length = edge.isVertical ? rect.height : rect.width
        let canonical = canonicalPath(in: CGRect(x: 0, y: 0, width: depth, height: length))
        return canonical
            .applying(Self.transform(for: edge, depth: depth))
            .applying(CGAffineTransform(translationX: rect.minX, y: rect.minY))
    }

    static func transform(for edge: NotchEdge, depth: CGFloat) -> CGAffineTransform {
        switch edge {
        case .right:
            return .identity
        case .left:
            return CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: depth, ty: 0)
        case .top:
            return CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: depth)
        case .bottom:
            return CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0)
        }
    }

    private func canonicalPath(in rect: CGRect) -> Path {
        let wanted = max(0, min(cornerRadius, rect.width / 2))
        let curl = max(0, min(curlRadius, rect.height / 2, rect.width - wanted))
        let corner = max(0, min(wanted, (rect.height - 2 * curl) / 2))
        let bodyTop = rect.minY + curl
        let bodyBottom = rect.maxY - curl

        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        if curl > 0 {
            path.addArc(
                center: CGPoint(x: rect.maxX - curl, y: rect.minY),
                radius: curl,
                startAngle: .degrees(0), endAngle: .degrees(90),
                clockwise: false
            )
        }
        path.addLine(to: CGPoint(x: rect.minX + corner, y: bodyTop))
        path.addArc(
            center: CGPoint(x: rect.minX + corner, y: bodyTop + corner),
            radius: corner,
            startAngle: .degrees(270), endAngle: .degrees(180),
            clockwise: true
        )
        path.addLine(to: CGPoint(x: rect.minX, y: bodyBottom - corner))
        path.addArc(
            center: CGPoint(x: rect.minX + corner, y: bodyBottom - corner),
            radius: corner,
            startAngle: .degrees(180), endAngle: .degrees(90),
            clockwise: true
        )
        path.addLine(to: CGPoint(x: rect.maxX - curl, y: bodyBottom))
        if curl > 0 {
            path.addArc(
                center: CGPoint(x: rect.maxX - curl, y: rect.maxY),
                radius: curl,
                startAngle: .degrees(270), endAngle: .degrees(360),
                clockwise: false
            )
        }
        path.closeSubpath()
        return path
    }
}

/// A single teardrop pulled from the card until its tip touches the rail.
struct LiquidNeck: Shape {
    let direction: NotchEdge.TooltipDirection

    func path(in rect: CGRect) -> Path {
        let canonicalSize: CGSize
        let transform: CGAffineTransform
        switch direction {
        case .leading:
            canonicalSize = rect.size
            transform = .identity
        case .trailing:
            canonicalSize = rect.size
            transform = CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: rect.width, ty: 0)
        case .down:
            canonicalSize = CGSize(width: rect.height, height: rect.width)
            transform = CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: rect.height)
        case .up:
            canonicalSize = CGSize(width: rect.height, height: rect.width)
            transform = CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0)
        }

        let canonical = CGRect(origin: .zero, size: canonicalSize)
        let anchorHalf = canonical.height * 0.44
        let anchorTop = canonical.midY - anchorHalf
        let anchorBottom = canonical.midY + anchorHalf

        var path = Path()
        path.move(to: CGPoint(x: canonical.minX, y: anchorTop))
        path.addCurve(
            to: CGPoint(x: canonical.maxX, y: canonical.midY),
            control1: CGPoint(x: canonical.width * 0.08, y: canonical.midY - canonical.height * 0.08),
            control2: CGPoint(x: canonical.width * 0.62, y: canonical.midY)
        )
        path.addCurve(
            to: CGPoint(x: canonical.minX, y: anchorBottom),
            control1: CGPoint(x: canonical.width * 0.62, y: canonical.midY),
            control2: CGPoint(x: canonical.width * 0.08, y: canonical.midY + canonical.height * 0.08)
        )
        path.closeSubpath()
        return path.applying(transform)
    }

    static func size(for direction: NotchEdge.TooltipDirection, cardAlong: CGFloat) -> CGSize {
        let straightCardEdge = max(0, cardAlong - 2 * HUDLayout.cardCorner)
        let rootLength = min(HUDLayout.tailHeight, straightCardEdge)
        switch direction {
        case .leading, .trailing:
            return CGSize(width: HUDLayout.tailLength, height: rootLength)
        case .up, .down:
            return CGSize(width: rootLength, height: HUDLayout.tailLength)
        }
    }
}
