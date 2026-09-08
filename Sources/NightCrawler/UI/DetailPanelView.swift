import SwiftUI

struct DetailPanelView: View {
    let reading: UsageReading
    let onClose: () -> Void

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

            if reading.status.isError || reading.status == .unknown {
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
                    ForEach(Array(reading.windows.enumerated()), id: \.element.id) { index, window in
                        WindowRow(window: window)
                            .padding(.top, index == 0 ? HUDLayout.headerToBlock : HUDLayout.blockSpacing)
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
                    Text(relativeTime(reset))
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .font(Typography.cardBody)
            .lineLimit(1)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Palette.barTrack)
                    .frame(width: trackWidth, height: HUDLayout.barHeight)
                Capsule()
                    .fill(band.color)
                    .frame(width: fillWidth, height: HUDLayout.barHeight)
            }
            .padding(.top, HUDLayout.labelToBar)

            Text("\(ProviderIcon.percentageText(for: window)) Used")
                .font(Typography.cardBody)
                .foregroundStyle(Palette.textPrimary)
                .padding(.top, HUDLayout.barToUsed)
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
