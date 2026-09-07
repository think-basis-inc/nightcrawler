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

/// A pinched tendril that makes the card read as liquid plastic pulled from one
/// small spot into the rail, rather than a triangular or full-edge funnel.
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
        let rootHalf = min(canonical.height * 0.17, Design.px(18))
        let swellHalf = min(canonical.height * 0.22, Design.px(24))
        let tipHalf = min(canonical.height * 0.14, Design.px(15))
        let rootTop = canonical.midY - rootHalf
        let rootBottom = canonical.midY + rootHalf
        let swellTop = canonical.midY - swellHalf
        let swellBottom = canonical.midY + swellHalf
        let tipTop = canonical.midY - tipHalf
        let tipBottom = canonical.midY + tipHalf
        let swellX = canonical.width * 0.44

        var path = Path()
        path.move(to: CGPoint(x: canonical.minX, y: rootTop))
        path.addCurve(
            to: CGPoint(x: swellX, y: swellTop),
            control1: CGPoint(x: canonical.width * 0.14, y: rootTop),
            control2: CGPoint(x: canonical.width * 0.27, y: swellTop)
        )
        path.addCurve(
            to: CGPoint(x: canonical.maxX, y: tipTop),
            control1: CGPoint(x: canonical.width * 0.68, y: swellTop),
            control2: CGPoint(x: canonical.width * 0.86, y: tipTop)
        )
        path.addLine(to: CGPoint(x: canonical.maxX, y: tipBottom))
        path.addCurve(
            to: CGPoint(x: swellX, y: swellBottom),
            control1: CGPoint(x: canonical.width * 0.86, y: tipBottom),
            control2: CGPoint(x: canonical.width * 0.68, y: swellBottom)
        )
        path.addCurve(
            to: CGPoint(x: canonical.minX, y: rootBottom),
            control1: CGPoint(x: canonical.width * 0.27, y: swellBottom),
            control2: CGPoint(x: canonical.width * 0.14, y: rootBottom)
        )
        path.closeSubpath()
        return path.applying(transform)
    }

    static func size(for direction: NotchEdge.TooltipDirection) -> CGSize {
        switch direction {
        case .leading, .trailing:
            return CGSize(width: HUDLayout.tailLength, height: HUDLayout.tailHeight)
        case .up, .down:
            return CGSize(width: HUDLayout.tailHeight, height: HUDLayout.tailLength)
        }
    }
}
