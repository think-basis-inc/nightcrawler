import AppKit

protocol ScreenDescribing {
    var frameValue: CGRect { get }
    var visibleFrameValue: CGRect { get }
}

extension NSScreen: ScreenDescribing {
    var frameValue: CGRect { frame }
    var visibleFrameValue: CGRect { visibleFrame }
}

enum NotchGeometry {
    static func panelFrame(
        for screen: ScreenDescribing,
        panelSize: CGSize,
        edge: NotchEdge = .right
    ) -> CGRect {
        let full = screen.frameValue
        let usable = screen.visibleFrameValue
        let width = panelSize.width.rounded(.up)
        let height = panelSize.height.rounded(.up)

        let origin: CGPoint
        switch edge {
        case .right:
            origin = CGPoint(x: usable.maxX - width, y: full.midY - height / 2)
        case .left:
            origin = CGPoint(x: usable.minX, y: full.midY - height / 2)
        case .top:
            origin = CGPoint(x: full.midX - width / 2, y: usable.maxY - height)
        case .bottom:
            origin = CGPoint(x: full.midX - width / 2, y: usable.minY)
        }

        return CGRect(
            x: origin.x.rounded(),
            y: origin.y.rounded(),
            width: width,
            height: height
        )
    }
}
