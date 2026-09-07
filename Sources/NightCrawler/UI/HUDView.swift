import SwiftUI

struct HUDView: View {
    @EnvironmentObject var store: UsageStore
    var onSelect: ((UsageReading) -> Void)?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: Design.px(83.5)) {
                ForEach(store.readings) { reading in
                    ProviderIcon(reading: reading)
                        .onTapGesture {
                            onSelect?(reading)
                        }
                }
            }
            .padding(.top, Design.px(69.5))
            .padding(.bottom, Design.px(50.1))
            .padding(.horizontal, 10)
        }
        .frame(width: Design.px(186))
        .background(
            RoundedRectangle(cornerRadius: Design.px(186) / 2, style: .continuous)
                .fill(Palette.notch)
        )
    }
}

struct ProviderIcon: View {
    let reading: UsageReading
    @State private var isHovered = false

    private var window: UsageWindow? { reading.headlineWindow }
    private var glyph: ProviderGlyph? { ProviderGlyph.from(providerId: reading.providerId) }

    var body: some View {
        VStack(spacing: Design.px(26.9)) {
            ZStack {
                Circle()
                    .stroke(Palette.ringTrack, lineWidth: Design.px(15.5))
                    .frame(width: Design.px(117), height: Design.px(117))

                if let window {
                    Circle()
                        .inset(by: Design.px(15.5) / 2)
                        .trim(from: 0, to: CGFloat(min(max(window.fraction, 0), 1)))
                        .stroke(
                            band.color,
                            style: StrokeStyle(lineWidth: Design.px(8), lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: Design.px(117), height: Design.px(117))
                }

                if let glyph {
                    ProviderGlyphView(glyph: glyph)
                        .foregroundStyle(Palette.textPrimary)
                } else {
                    Text(initials)
                        .font(.system(size: Design.fontSize(capPixels: 46), weight: .bold))
                        .foregroundStyle(Palette.textPrimary)
                }
            }
            .frame(width: Design.px(117), height: Design.px(117))

            Text(percentageText)
                .font(Typography.percent)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: true, vertical: false)
                .frame(height: Design.px(27))
        }
        .scaleEffect(isHovered ? 1.04 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isHovered)
        .onHover { isHovered in
            self.isHovered = isHovered
        }
        .help(helpText)
    }

    private var band: UsageBand {
        guard let window else { return .unknown }
        return UsageBand.band(for: window.fraction)
    }

    private var initials: String {
        let words = reading.label.components(separatedBy: .whitespacesAndNewlines)
        let chars = words.compactMap { $0.first }
        return String(chars.prefix(2)).uppercased()
    }

    private var percentageText: String {
        guard !reading.status.isError, let window else { return "—" }
        return "\(Int(window.usedPercent))%"
    }

    private var helpText: String {
        switch reading.status {
        case .needsAuth:
            return "\(reading.label): sign in required"
        case .error(let error):
            return "\(reading.label): \(error)"
        case .live:
            guard let window else { return "\(reading.label): no reading" }
            return "\(reading.label): \(Int(window.usedPercent))% of \(window.limit) \(window.label)"
        }
    }
}

enum UsageBand {
    case ample, watch, critical, unknown

    static func band(for fraction: Double) -> UsageBand {
        switch fraction {
        case ..<0.7: return .ample
        case ..<0.9: return .watch
        default: return .critical
        }
    }

    var color: Color {
        switch self {
        case .ample: return Palette.ample
        case .watch: return Palette.watch
        case .critical: return Palette.critical
        case .unknown: return Palette.textSecondary
        }
    }
}

extension ProviderGlyph {
    static func from(providerId id: String) -> ProviderGlyph? {
        switch id {
        case "claude": return .claude
        case "codex": return .openai
        case "cursor": return .cursor
        case "copilot": return .third
        case "grok": return .grok
        case "gemini", "antigravity": return .antigravity
        case "opencode": return .opencode
        case "zcode": return .glm
        default: return nil
        }
    }
}
