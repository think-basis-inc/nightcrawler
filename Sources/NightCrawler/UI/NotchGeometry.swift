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
        edge: NotchEdge = .right,
        cellCount: Int? = nil
    ) -> CGRect {
        let full = screen.frameValue
        let usable = screen.visibleFrameValue
        let width = panelSize.width.rounded(.up)
        let height = panelSize.height.rounded(.up)

        let origin: CGPoint
        switch edge {
        case .right, .left:
            let defaultY = full.midY - height / 2
            let slack = HUDLayout.slack(for: edge)
            let shapeLength = max(0, height - 2 * slack)
            let start = HUDLayout.padStart(for: edge)
            let end = HUDLayout.padEnd(for: edge)
            let flare = HUDLayout.curlRadius
            let pitch = HUDLayout.cellPitch(for: edge)
            let inferredCount = max(1, Int(round((shapeLength - 2 * flare - start - end + HUDLayout.cellSpacing) / pitch)))
            let effectiveCount = cellCount ?? inferredCount
            let lowestRingAlong = slack + HUDLayout.ringCenter(index: max(0, effectiveCount - 1), edge: edge)
            let maxCardHeight = HUDLayout.defaultMaxCardHeight
            let maxBottomInPanel = lowestRingAlong + maxCardHeight / 2
            let minYForBottomCard = (usable.minY - (height - maxBottomInPanel)).rounded(.up)
            let y = max(defaultY, minYForBottomCard)
            let x = edge == .right ? usable.maxX - width : usable.minX
            origin = CGPoint(x: x, y: y)

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

    static func settingsCardScreenRect(
        for screen: ScreenDescribing,
        cellCount: Int,
        edge: NotchEdge = .right,
        providerCount: Int = 11,
        routingToolCount: Int = 2,
        displayRowCount: Int = 2
    ) -> CGRect {
        let cardHeight = HUDLayout.settingsCardHeight(
            providerCount: providerCount,
            routingToolCount: routingToolCount,
            displayRowCount: displayRowCount
        )
        let cardWidth = HUDLayout.cardWidth
        let panelSize = HUDLayout.panelSize(cellCount: cellCount, edge: edge)
        let panelFrame = NotchGeometry.panelFrame(
            for: screen,
            panelSize: panelSize,
            edge: edge,
            cellCount: cellCount
        )
        let slack = HUDLayout.slack(for: edge)
        let index = max(cellCount - 1, 0)
        let along = slack + HUDLayout.ringCenter(index: index, edge: edge)
        let cardAlong = edge.isVertical ? cardWidth : cardHeight
        let center = HUDLayout.attachedSlideoutCenter(
            edge: edge,
            panelSize: panelSize,
            ringCenterAlong: along,
            cardAlong: cardAlong,
            tailLength: HUDLayout.tailLength,
            railDepth: HUDLayout.bodyDepth(for: edge),
            slack: slack
        )
        let shellSize = CGSize(
            width: edge.isVertical ? cardWidth + HUDLayout.tailLength : cardWidth,
            height: edge.isVertical ? cardHeight : cardHeight + HUDLayout.tailLength
        )
        let cardMinX: CGFloat
        let cardMaxY: CGFloat
        switch edge {
        case .right:
            cardMinX = center.x - shellSize.width / 2
            cardMaxY = center.y + cardHeight / 2
        case .left:
            cardMinX = center.x - shellSize.width / 2 + HUDLayout.tailLength
            cardMaxY = center.y + cardHeight / 2
        case .top:
            cardMinX = center.x - cardWidth / 2
            cardMaxY = center.y + shellSize.height / 2
        case .bottom:
            cardMinX = center.x - cardWidth / 2
            cardMaxY = center.y - shellSize.height / 2 + cardHeight
        }
        let originX = panelFrame.minX + cardMinX
        let originY = panelFrame.maxY - cardMaxY
        return CGRect(x: originX, y: originY, width: cardWidth, height: cardHeight)
    }
}
