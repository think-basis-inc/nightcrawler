import SwiftUI

struct DetailPanelView: View {
    let reading: UsageReading
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Design.px(17)) {
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
                .buttonStyle(.borderless)
                .foregroundStyle(Palette.textSecondary)
            }

            if reading.status.isError {
                Text(statusMessage)
                    .font(Typography.cardBody)
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.top, Design.px(21))
            } else if reading.windows.isEmpty {
                Text("No usage windows reported.")
                    .font(Typography.cardBody)
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.top, Design.px(21))
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(reading.windows.enumerated()), id: \.element.id) { index, window in
                        WindowRow(window: window)
                            .padding(.top, index == 0 ? Design.px(21) : Design.px(20))
                    }
                }
            }
        }
        .padding(Design.px(32))
        .padding(.trailing, 12 + Design.px(32))
        .frame(width: 260, alignment: .leading)
        .background(
            DetailPanelShape(cornerRadius: Design.px(49.5), tailSize: CGSize(width: 12, height: 24))
                .fill(Palette.card)
        )
        .foregroundStyle(Palette.textPrimary)
    }

    private var statusMessage: String {
        switch reading.status {
        case .needsAuth:
            return reading.error ?? "Sign in required"
        case .error(let message):
            return message
        case .live:
            return ""
        }
    }
}

struct WindowRow: View {
    let window: UsageWindow

    private var band: UsageBand { UsageBand.band(for: window.fraction) }
    private var trackWidth: CGFloat { 260 - 12 - 2 * Design.px(32) }
    private var fillWidth: CGFloat { max(Design.px(10.5), trackWidth * min(window.fraction, 1)) }

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
                    .frame(width: trackWidth, height: Design.px(10.5))
                Capsule()
                    .fill(band.color)
                    .frame(width: fillWidth, height: Design.px(10.5))
            }
            .padding(.top, Design.px(16.8))

            Text("\(Int(window.usedPercent))% Used")
                .font(Typography.cardBody)
                .foregroundStyle(Palette.textPrimary)
                .padding(.top, Design.px(17.8))
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
