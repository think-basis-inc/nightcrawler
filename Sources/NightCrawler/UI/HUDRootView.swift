import SwiftUI

struct HUDRootView: View {
    @EnvironmentObject var store: UsageStore
    @Binding var surface: HUDSurfaceState
    @Binding var isExternallyHovered: Bool
    var edge: NotchEdge
    var isMiniModeEnabled: Bool = false
    var isAutoHideEnabled: Bool = false
    var railFitScale: CGFloat = 1
    var onSelect: (UsageReading) -> Void
    var onSettings: () -> Void
    var onEdgeChange: (NotchEdge) -> Void
    var onMiniModeChange: (Bool) -> Void = { _ in }
    var onAutoHideChange: (Bool) -> Void = { _ in }
    var onHoverChange: (Bool) -> Void = { _ in }
    var onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoveringRail = false
    @State private var hoveringSettings = false

    var body: some View {
        GeometryReader { proxy in
            let place = NotchPlacement(edge: edge, panelSize: proxy.size)
            ZStack(alignment: .topLeading) {
                Color.clear
                rail(place)
                settingsHandle(place)
                if let slideout = slideoutContent {
                    slideoutView(place, slideout)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private var readings: [UsageReading] { store.orderedReadings }
    private var cellCount: Int { max(readings.count, 1) }
    private var slack: CGFloat { HUDLayout.slack(for: edge) }
    private var flare: CGFloat { HUDLayout.curlRadius }
    private var shapeLength: CGFloat { HUDLayout.shapeLength(cellCount: cellCount, edge: edge) }
    private var notchDepth: CGFloat { HUDLayout.bodyDepth(for: edge) }
    private var notchSize: CGSize {
        NotchPlacement.panelSize(edge: edge, length: shapeLength, depth: notchDepth)
    }
    var tabScale: CGFloat {
        HUDLayout.railScale(
            miniMode: isMiniModeEnabled,
            isHovered: hoveringRail || hoveringSettings || isExternallyHovered || surface.mode != .idle,
            fitScale: railFitScale
        )
    }

    private func rail(_ place: NotchPlacement) -> some View {
        SideNotchShape(edge: edge)
            .fill(Palette.notch)
            .frame(width: notchSize.width, height: notchSize.height)
            .overlay(alignment: contentAlignment) {
                cells.padding(bezelSide, 0)
            }
            .clipShape(SideNotchShape(edge: edge))
            .contentShape(SideNotchShape(edge: edge))
            .onHover { isHovered in
                hoveringRail = isHovered
                isExternallyHovered = isHovered
                onHoverChange(isHovered)
            }
            .scaleEffect(tabScale, anchor: tabScaleAnchor)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: tabScale)
            .position(place.point(
                along: slack + shapeLength / 2,
                across: notchDepth / 2
            ))
    }

    @ViewBuilder
    private var cells: some View {
        let stack = ForEach(Array(readings.enumerated()), id: \.element.id) { _, reading in
            Button(action: { onSelect(reading) }) {
                ProviderIcon(reading: reading)
                    .frame(width: edge.isVertical ? nil : HUDLayout.cellAlong(for: edge))
            }
            .buttonStyle(.plain)
        }
        Group {
            if edge.isVertical {
                VStack(spacing: HUDLayout.cellSpacing) { stack }
                    .padding(.top, flare + HUDLayout.padStart(for: edge))
                    .frame(width: HUDLayout.bodyDepth(for: edge))
            } else {
                HStack(spacing: HUDLayout.cellSpacing) { stack }
                    .padding(.leading, flare + HUDLayout.padStart(for: edge))
                    .frame(height: HUDLayout.bodyDepth(for: edge))
            }
        }
    }

    private var contentAlignment: Alignment {
        switch edge {
        case .right: return .topTrailing
        case .left: return .topLeading
        case .top: return .topLeading
        case .bottom: return .bottomLeading
        }
    }

    private var bezelSide: Edge.Set {
        switch edge {
        case .right: return .trailing
        case .left: return .leading
        case .top: return .top
        case .bottom: return .bottom
        }
    }

    private func settingsHandle(_ place: NotchPlacement) -> some View {
        Button(action: onSettings) {
            SettingsOrb(isHovered: hoveringSettings, edge: edge)
        }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .onHover { isHovered in
                hoveringSettings = isHovered
                isExternallyHovered = isHovered
                onHoverChange(isHovered)
            }
            .scaleEffect(tabScale)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: tabScale)
            .position(place.point(
                along: scaledTabAlong(slack + shapeLength),
                across: HUDLayout.orbInsetFromEdge * tabScale
            ))
            .accessibilityLabel("Settings")
    }

    private var tabScaleAnchor: UnitPoint {
        switch edge {
        case .right: return .trailing
        case .left: return .leading
        case .top: return .top
        case .bottom: return .bottom
        }
    }

    private func scaledTabAlong(_ along: CGFloat) -> CGFloat {
        let railCenter = slack + shapeLength / 2
        return railCenter + (along - railCenter) * tabScale
    }

    private enum Slideout {
        case detail(UsageReading)
        case settings
    }

    private var slideoutContent: Slideout? {
        switch surface.mode {
        case .idle:
            return nil
        case .detail(let id):
            if let reading = readings.first(where: { $0.providerId == id }) {
                return .detail(reading)
            }
            return nil
        case .settings:
            return .settings
        }
    }

    @ViewBuilder
    private func slideoutView(_ place: NotchPlacement, _ content: Slideout) -> some View {
        let direction = edge.tooltipDirection
        let index: Int = {
            if case .detail(let reading) = content,
               let found = readings.firstIndex(where: { $0.providerId == reading.providerId }) {
                return found
            }
            return max(readings.count - 1, 0)
        }()
        let height: CGFloat = {
            switch content {
            case .detail(let reading):
                return HUDLayout.cardHeight(windowCount: max(reading.windows.count, 1))
            case .settings:
                return HUDLayout.settingsCardHeight(
                    providerCount: store.providerCatalog.count,
                    routingToolCount: store.routingToolStates.count
                )
            }
        }()
        let cardAlong = edge.isVertical ? HUDLayout.cardWidth : height
        let along = scaledTabAlong(slack + HUDLayout.ringCenter(index: index, edge: edge))
        let center = HUDLayout.attachedSlideoutCenter(
            edge: edge,
            panelSize: place.panelSize,
            ringCenterAlong: along,
            cardAlong: cardAlong,
            tailLength: HUDLayout.tailLength,
            railDepth: notchDepth,
            slack: slack
        )

        SlideoutShell(
            height: height,
            direction: direction,
            onHoverChange: onHoverChange
        ) {
            switch content {
            case .detail(let reading):
                DetailPanelView(reading: reading, onClose: onDismiss)
            case .settings:
                ScrollView(.vertical) {
                    SettingsView(
                        edge: edge,
                        isMiniModeEnabled: isMiniModeEnabled,
                        isAutoHideEnabled: isAutoHideEnabled,
                        onEdgeChange: onEdgeChange,
                        onMiniModeChange: onMiniModeChange,
                        onAutoHideChange: onAutoHideChange
                    )
                }
            }
        }
        .position(center)
        .transition(.opacity)
        .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.86), value: surface.mode)
    }
}

private struct SlideoutShell<Content: View>: View {
    let height: CGFloat
    let direction: NotchEdge.TooltipDirection
    var onHoverChange: (Bool) -> Void = { _ in }
    @ViewBuilder let content: Content

    var body: some View {
        let cardAlong = direction == .leading || direction == .trailing
            ? height
            : HUDLayout.cardWidth
        let tailSize = LiquidNeck.size(for: direction, cardAlong: cardAlong)
        let card = content
            .padding(HUDLayout.cardPadding)
            .frame(width: HUDLayout.cardWidth, height: height, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: HUDLayout.cardCorner, style: .circular)
                    .fill(Palette.card)
            )
            .clipShape(RoundedRectangle(cornerRadius: HUDLayout.cardCorner, style: .circular))

        let tail = LiquidNeck(direction: direction)
            .fill(Palette.card)
            .frame(width: tailSize.width, height: tailSize.height)

        Group {
            switch direction {
            case .leading:
                HStack(spacing: 0) { card; tail }
            case .trailing:
                HStack(spacing: 0) { tail; card }
            case .down:
                VStack(spacing: 0) { tail; card }
            case .up:
                VStack(spacing: 0) { card; tail }
            }
        }
        .onHover { onHoverChange($0) }
    }
}
