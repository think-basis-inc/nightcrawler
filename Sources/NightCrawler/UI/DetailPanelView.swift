import SwiftUI

struct DetailPanelView: View {
    let reading: UsageReading
    var onSignIn: () -> Void = {}
    let onClose: () -> Void

    static func signInMethod(
        for reading: UsageReading,
        isInstalled: (ProviderSignIn) -> Bool = ProviderSignIn.isInstalled
    ) -> ProviderSignIn? {
        if case .signIn(let method) = HUDIconAction.resolve(for: reading, isInstalled: isInstalled) {
            return method
        }
        return nil
    }

    static func cardHeight(for reading: UsageReading) -> CGFloat {
        signInMethod(for: reading) != nil
            ? HUDLayout.signInCardHeight
            : HUDLayout.cardHeight(windowCount: max(reading.windows.count, 1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: HUDLayout.headerGap) {
                if let glyph = ProviderGlyph.from(providerId: reading.providerId) {
                    ProviderGlyphView(glyph: glyph)
                        .foregroundStyle(Palette.textPrimary)
                }
                Text("\(reading.label) Usage")
                    .font(Typography.cardTitle)
                    .foregroundStyle(Palette.textPrimary)
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(Typography.cardBody)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.textSecondary)
                .accessibilityLabel("Close")
            }

            if let method = Self.signInMethod(for: reading) {
                Text(statusMessage)
                    .font(Typography.cardBody)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(2)
                    .frame(height: 2 * HUDLayout.cardBodyLineHeight, alignment: .topLeading)
                    .padding(.top, HUDLayout.headerToBlock)
                Button(action: onSignIn) {
                    Text("Sign in")
                        .font(Typography.cardBody)
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, Design.px(20))
                        .frame(height: HUDLayout.edgePickerHeight)
                        .background(Capsule().fill(Palette.ample))
                }
                .buttonStyle(.plain)
                .padding(.top, HUDLayout.blockSpacing)
                .accessibilityLabel("Sign in to \(reading.label)")
                Text(method.hint)
                    .font(Typography.cardBody)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.top, HUDLayout.labelToBar)
            } else if reading.status.isError || reading.status == .unknown {
                Text(statusMessage)
                    .font(Typography.cardBody)
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.top, HUDLayout.headerToBlock)
            } else if reading.windows.isEmpty {
                Text("No usage windows reported.")
                    .font(Typography.cardBody)
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.top, HUDLayout.headerToBlock)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    if !reading.isFreshlyObserved() {
                        Text("Last reading is stale")
                            .font(Typography.cardBody)
                            .foregroundStyle(Palette.textSecondary)
                            .padding(.top, HUDLayout.headerToBlock)
                    }
                    ForEach(Array(reading.displayWindows.enumerated()), id: \.element.id) { index, window in
                        WindowRow(window: window)
                            .padding(.top, index == 0 && reading.isFreshlyObserved() ? HUDLayout.headerToBlock : HUDLayout.blockSpacing)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(Palette.textPrimary)
    }

    private var statusMessage: String {
        switch reading.status {
        case .needsAuth:
            return reading.error ?? "Sign in required"
        case .error(let message):
            return message
        case .unknown:
            return reading.error ?? "No finite allowance reported"
        case .live:
            return ""
        }
    }
}

struct WindowRow: View {
    let window: UsageWindow

    private var band: UsageBand { UsageBand.band(for: window.fraction) }
    private var trackWidth: CGFloat { HUDLayout.cardWidth - 2 * HUDLayout.cardPadding }
    private var fillWidth: CGFloat { max(HUDLayout.barHeight, trackWidth * min(window.fraction, 1)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Design.px(20)) {
                Text(window.label)
                    .foregroundStyle(Palette.textPrimary)
                Spacer(minLength: 0)
                if let reset = window.resetsAt {
                    Text(ResetClock.caption(for: reset))
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .font(Typography.cardBody)
            .lineLimit(1)

            if window.limit > 0 {
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Palette.barTrack)
                        .frame(width: trackWidth, height: HUDLayout.barHeight)
                    Capsule()
                        .fill(band.color)
                        .frame(width: fillWidth, height: HUDLayout.barHeight)
                }
                .padding(.top, HUDLayout.labelToBar)
            }

            Text(UsageCaption.line(for: window))
                .font(Typography.cardBody)
                .foregroundStyle(Palette.textPrimary)
                .padding(.top, window.limit > 0 ? HUDLayout.barToUsed : HUDLayout.labelToBar)
        }
    }
}
