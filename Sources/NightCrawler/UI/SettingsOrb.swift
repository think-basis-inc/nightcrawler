import SwiftUI

struct SettingsOrb: View {
    let isHovered: Bool
    var edge: NotchEdge = .right

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static func restingTrim(for edge: NotchEdge) -> ClosedRange<CGFloat> {
        switch edge {
        case .right: return 0.75...1.0
        case .left: return 0.5...0.75
        case .top: return 0.5...0.75
        case .bottom: return 0.25...0.5
        }
    }

    var body: some View {
        let trim = Self.restingTrim(for: edge)
        ZStack {
            Circle()
                .trim(from: trim.lowerBound, to: trim.upperBound)
                .stroke(
                    Palette.notch,
                    style: StrokeStyle(lineWidth: HUDLayout.orbStroke, lineCap: .round)
                )
                .frame(width: HUDLayout.orbArcRadius * 2, height: HUDLayout.orbArcRadius * 2)
                .opacity(isHovered ? 0 : 1)
                .scaleEffect(isHovered ? 0.86 : 1)

            Circle()
                .fill(Palette.notch)
                .frame(width: HUDLayout.orbDiameter, height: HUDLayout.orbDiameter)
                .opacity(isHovered ? 1 : 0)
                .scaleEffect(isHovered ? 1 : 1.1)

            Image(systemName: "gearshape")
                .font(.system(size: HUDLayout.orbGlyph, weight: .regular))
                .foregroundStyle(Palette.textPrimary)
                .opacity(isHovered ? 1 : 0)
                .scaleEffect(isHovered ? 1 : 0.5)
                .rotationEffect(.degrees(isHovered ? 0 : -60))
        }
        .frame(
            width: HUDLayout.orbArcRadius * 2 + HUDLayout.orbStroke,
            height: HUDLayout.orbArcRadius * 2 + HUDLayout.orbStroke
        )
        .animation(
            reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.7),
            value: isHovered
        )
        .accessibilityLabel("Settings")
        .accessibilityAddTraits(.isButton)
    }
}
