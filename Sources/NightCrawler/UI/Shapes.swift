import SwiftUI

struct HUDTabShape: Shape {
    var selectedIndex: Int?
    var cornerRadius: CGFloat
    var notchSize: CGSize

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRoundedRect(
            in: rect,
            cornerSize: CGSize(width: cornerRadius, height: cornerRadius),
            style: .continuous
        )

        if let index = selectedIndex {
            let y = iconCenterY(for: index, in: rect)
            let halfHeight = notchSize.height / 2
            var notch = Path()
            notch.move(to: CGPoint(x: rect.minX, y: y - halfHeight))
            notch.addLine(to: CGPoint(x: rect.minX + notchSize.width, y: y))
            notch.addLine(to: CGPoint(x: rect.minX, y: y + halfHeight))
            notch.closeSubpath()
            path.addPath(notch)
        }
        return path
    }

    private func iconCenterY(for index: Int, in rect: CGRect) -> CGFloat {
        let padTop = Design.px(69.5)
        let ringDiameter = Design.px(117)
        let ringLabelGap = Design.px(26.9)
        let percentHeight = Design.px(27)
        let cellExtent = ringDiameter + ringLabelGap + percentHeight
        let cellSpacing = Design.px(83.5)
        let raw = padTop + ringDiameter / 2 + CGFloat(index) * (cellExtent + cellSpacing)
        return min(max(raw, cornerRadius + notchSize.height / 2), rect.height - cornerRadius - notchSize.height / 2)
    }
}

struct DetailPanelShape: Shape {
    var cornerRadius: CGFloat
    var tailSize: CGSize

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let contentWidth = rect.width - tailSize.width
        let bodyRect = CGRect(x: rect.minX, y: rect.minY, width: contentWidth, height: rect.height)
        path.addRoundedRect(
            in: bodyRect,
            cornerSize: CGSize(width: cornerRadius, height: cornerRadius),
            style: .continuous
        )

        let y = rect.midY
        let halfHeight = tailSize.height / 2
        var tail = Path()
        tail.move(to: CGPoint(x: bodyRect.maxX, y: y - halfHeight))
        tail.addLine(to: CGPoint(x: rect.maxX, y: y))
        tail.addLine(to: CGPoint(x: bodyRect.maxX, y: y + halfHeight))
        tail.closeSubpath()
        path.addPath(tail)
        return path
    }
}
