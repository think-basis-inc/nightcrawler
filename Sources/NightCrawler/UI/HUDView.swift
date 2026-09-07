import SwiftUI

struct HUDView: View {
    @EnvironmentObject var store: UsageStore
    var onSelect: ((UsageReading) -> Void)?
    var onSettings: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
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

            Image(systemName: "gearshape")
                .font(.system(size: Design.fontSize(capPixels: 32)))
                .foregroundStyle(Palette.textSecondary)
                .frame(width: Design.px(56), height: Design.px(56))
                .background(Circle().fill(Palette.ringTrack))
                .onTapGesture {
                    onSettings?()
                }
                .padding(.bottom, Design.px(24))
        }
        .frame(width: Design.px(186))
        .background(
            TabPillShape(cornerRadius: Design.px(186) / 2, notchSize: CGSize(width: 12, height: 24))
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

                if reading.status == .live, let window {
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

                if reading.status.isError {
                    Circle()
                        .stroke(Palette.textSecondary, lineWidth: Design.px(8))
                        .frame(width: Design.px(117), height: Design.px(117))
                }
            }
            .frame(width: Design.px(117), height: Design.px(117))

            Text(percentageText)
                .font(Typography.percent)
                .foregroundStyle(reading.status.isError ? Palette.textSecondary : Palette.textPrimary)
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

struct TabPillShape: Shape {
    var cornerRadius: CGFloat
    var notchSize: CGSize

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRoundedRect(
            in: rect,
            cornerSize: CGSize(width: cornerRadius, height: cornerRadius),
            style: .continuous
        )

        let y = rect.midY
        let halfHeight = notchSize.height / 2
        var tab = Path()
        tab.move(to: CGPoint(x: rect.minX, y: y - halfHeight))
        tab.addLine(to: CGPoint(x: rect.minX - notchSize.width, y: y))
        tab.addLine(to: CGPoint(x: rect.minX, y: y + halfHeight))
        tab.closeSubpath()

        path.addPath(tab)
        return path
    }
}
