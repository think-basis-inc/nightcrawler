import Foundation

enum HUDLayout {
    static let sideBodyDepth = Design.px(186)
    static let curlRadius = Design.px(103)
    static let cornerRadius = Design.px(78.8)
    static let padTop = Design.px(69.5)
    static let padBottom = Design.px(50.1)
    static let cellSpacing = Design.px(83.5)
    static let ringDiameter = Design.px(117)
    static let trackStroke = Design.px(15.5)
    static let progressStroke = Design.px(8)
    static let innerProgressStroke = Design.px(5.5)
    static let glyphSize = Design.px(46)
    static let ringLabelGap = Design.px(26.9)
    static let percentLineHeight = Design.px(27)
    static let tailLength = Design.px(75)
    static let tailHeight = Design.px(87)
    static let tailGap: CGFloat = 0
    static let cardWidth = Design.px(600)
    static let cardCorner = Design.px(49.5)
    static let cardPadding = Design.px(32)
    static let orbDiameter = Design.px(124)
    static let orbStroke = Design.px(18)
    static let orbGap = Design.px(27)
    static var orbArcRadius: CGFloat { curlRadius - orbGap }
    static let orbGlyph = Design.px(56)
    static var orbInsetFromEdge: CGFloat { curlRadius }
    static let barHeight = Design.px(10.5)
    static let headerGap = Design.px(17)
    static let headerToBlock = Design.px(21)
    static let labelToBar = Design.px(16.8)
    static let barToUsed = Design.px(17.8)
    static let blockSpacing = Design.px(20)
    static let cardBodyLineHeight = Design.px(25)
    static let cardTitleLineHeight = Design.px(36)
    static let edgePickerHeight = Design.px(42)

    static func bodyDepth(for edge: NotchEdge) -> CGFloat {
        edge.isVertical ? sideBodyDepth : 2 * sideRingMargin + cellExtent
    }

    private static var sideRingMargin: CGFloat { (sideBodyDepth - ringDiameter) / 2 }

    static var cellExtent: CGFloat { ringDiameter + ringLabelGap + percentLineHeight }

    static func cellAlong(for edge: NotchEdge) -> CGFloat {
        edge.isVertical ? cellExtent : ringDiameter
    }

    static func cellPitch(for edge: NotchEdge) -> CGFloat {
        cellAlong(for: edge) + cellSpacing
    }

    static func padStart(for edge: NotchEdge) -> CGFloat {
        edge.isVertical ? padTop : (padTop + padBottom) / 2
    }

    static func padEnd(for edge: NotchEdge) -> CGFloat {
        edge.isVertical ? padBottom : (padTop + padBottom) / 2
    }

    static func bodyLength(cellCount: Int, edge: NotchEdge = .right) -> CGFloat {
        let start = padStart(for: edge)
        let end = padEnd(for: edge)
        guard cellCount > 0 else { return start + end }
        return start
            + CGFloat(cellCount) * cellAlong(for: edge)
            + CGFloat(cellCount - 1) * cellSpacing
            + end
    }

    static func shapeLength(cellCount: Int, edge: NotchEdge = .right, flare: CGFloat = curlRadius) -> CGFloat {
        bodyLength(cellCount: cellCount, edge: edge) + 2 * flare
    }

    static func ringCenter(index: Int, edge: NotchEdge = .right, flare: CGFloat = curlRadius) -> CGFloat {
        flare + padStart(for: edge) + ringDiameter / 2 + CGFloat(index) * cellPitch(for: edge)
    }

    static func slack(for edge: NotchEdge, maxCardHeight: CGFloat = defaultMaxCardHeight) -> CGFloat {
        edge.isVertical
            ? max(Design.px(190), maxCardHeight / 2 + cardCorner)
            : max(Design.px(190), cardWidth / 2 + cardCorner)
    }

    static func tooltipDepth(for edge: NotchEdge, maxCardHeight: CGFloat = defaultMaxCardHeight) -> CGFloat {
        (edge.isVertical ? cardWidth : maxCardHeight) + tailLength + tailGap
    }

    static func cardHeight(windowCount: Int, statusMessage: String? = nil) -> CGFloat {
        let header = max(glyphSize, cardTitleLineHeight)
        var height = 2 * cardPadding + header
        if windowCount > 0 {
            let block = 2 * cardBodyLineHeight + labelToBar + barHeight + barToUsed
            height += headerToBlock
                + CGFloat(windowCount) * block
                + CGFloat(max(0, windowCount - 1)) * blockSpacing
        } else {
            height += headerToBlock + cardBodyLineHeight
        }
        return height
    }

    static func settingsCardHeight(providerCount: Int, routingToolCount: Int) -> CGFloat {
        let rowHeight = max(glyphSize, Design.px(30))
        let edgeSection = cardTitleLineHeight + headerToBlock + edgePickerHeight + 2 * blockSpacing
        let providerRows = CGFloat(max(providerCount, 0)) * rowHeight
            + CGFloat(max(providerCount - 1, 0)) * blockSpacing
        let routingRowHeight = 2 * rowHeight + Design.px(10)
        let routingRows = CGFloat(max(routingToolCount, 0)) * routingRowHeight
            + CGFloat(max(routingToolCount - 1, 0)) * blockSpacing
        let routingSection = routingToolCount > 0
            ? 2 * blockSpacing + cardTitleLineHeight + headerToBlock + routingRows
            : 0
        return 2 * cardPadding + edgeSection + cardTitleLineHeight + headerToBlock + providerRows + routingSection
    }

    static let defaultMaxCardHeight = max(
        cardHeight(windowCount: 4),
        settingsCardHeight(providerCount: 9, routingToolCount: 2)
    )

    static func panelSize(cellCount: Int, edge: NotchEdge) -> CGSize {
        let card = defaultMaxCardHeight
        return NotchPlacement.panelSize(
            edge: edge,
            length: shapeLength(cellCount: cellCount, edge: edge) + 2 * slack(for: edge, maxCardHeight: card),
            depth: tooltipDepth(for: edge, maxCardHeight: card) + bodyDepth(for: edge)
        )
    }

    static func attachedSlideoutCenter(
        edge: NotchEdge,
        panelSize: CGSize,
        ringCenterAlong: CGFloat,
        cardAlong: CGFloat,
        tailLength: CGFloat,
        railDepth: CGFloat,
        slack: CGFloat
    ) -> CGPoint {
        let placement = NotchPlacement(edge: edge, panelSize: panelSize)
        let across = railDepth + tailGap + (tailLength + cardAlong) / 2
        return placement.point(along: ringCenterAlong, across: across)
    }
}
