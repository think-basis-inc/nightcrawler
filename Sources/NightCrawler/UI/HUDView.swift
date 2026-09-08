import SwiftUI

struct ProviderIcon: View {
    let reading: UsageReading
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    private var glyph: ProviderGlyph? { ProviderGlyph.from(providerId: reading.providerId) }

    var body: some View {
        VStack(spacing: percentageText == nil ? 0 : HUDLayout.ringLabelGap) {
            ZStack {
                Circle()
                    .stroke(Palette.ringTrack, lineWidth: HUDLayout.trackStroke)
                    .frame(width: HUDLayout.ringDiameter, height: HUDLayout.ringDiameter)

                if reading.status == .live, let outer = reading.outerRingWindow {
                    usageArc(window: outer, inset: HUDLayout.trackStroke / 2, lineWidth: HUDLayout.progressStroke)
                }

                if reading.status == .live, let inner = reading.innerRingWindow {
                    usageArc(
                        window: inner,
                        inset: HUDLayout.trackStroke + HUDLayout.progressStroke,
                        lineWidth: HUDLayout.innerProgressStroke
                    )
                }

                if let glyph {
                    ProviderGlyphView(glyph: glyph)
                        .foregroundStyle(sessionAlertColor)
                } else {
                    Text(initials)
                        .font(.system(size: Design.fontSize(capPixels: 46), weight: .bold))
                        .foregroundStyle(Palette.textPrimary)
                }

                if reading.status.isError {
                    Circle()
                        .stroke(Palette.textSecondary, lineWidth: HUDLayout.progressStroke)
                        .frame(width: HUDLayout.ringDiameter, height: HUDLayout.ringDiameter)
                }
            }
            .frame(width: HUDLayout.ringDiameter, height: HUDLayout.ringDiameter)
            // Strokes and glyph paths hit-test on their ink alone, which leaves
            // the ring interior (and the hollow of glyphs like the OpenAI
            // knot) dead to the pointer. Make the whole circle the target.
            .contentShape(Circle())

            if let percentageText {
                Text(percentageText)
                    .font(Typography.percent)
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(height: HUDLayout.percentLineHeight)
            }
        }
        .scaleEffect(isHovered && !reduceMotion ? 1.04 : 1.0)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.1), value: isHovered)
        .onHover { isHovered in
            self.isHovered = isHovered
        }
        .help(helpText)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(reading.label)
        .accessibilityValue(percentageAccessibilityText)
    }

    private func usageArc(window: UsageWindow, inset: CGFloat, lineWidth: CGFloat) -> some View {
        Circle()
            .inset(by: inset)
            .trim(from: 0, to: CGFloat(min(max(window.fraction, 0), 1)))
            .stroke(
                UsageBand.band(for: window.fraction).color,
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
            .rotationEffect(.degrees(-90))
            .frame(width: HUDLayout.ringDiameter, height: HUDLayout.ringDiameter)
    }

    private var initials: String {
        let words = reading.label.components(separatedBy: .whitespacesAndNewlines)
        let chars = words.compactMap { $0.first }
        return String(chars.prefix(2)).uppercased()
    }

    private var sessionAlertColor: Color {
        switch Self.sessionAlertBand(for: reading) {
        case .watch: return Palette.sessionWatch
        case .critical, .exhausted: return Palette.critical
        default: return Palette.textPrimary
        }
    }

    static func sessionAlertBand(for reading: UsageReading) -> UsageBand? {
        guard reading.status == .live,
              let session = reading.windows.first(where: {
                  $0.id == "session" || $0.windowMinutes == 300
              })
        else { return nil }
        let band = UsageBand.band(for: session.fraction)
        return band == .ample ? nil : band
    }

    private var percentageText: String? {
        Self.percentageText(for: reading)
    }

    private var percentageAccessibilityText: String {
        guard !reading.status.isError else { return "Unavailable" }
        guard let window = reading.outerRingWindow else {
            return reading.error ?? "No finite allowance reported"
        }
        return Self.accessibilityText(for: window)
    }

    static func percentageText(for window: UsageWindow) -> String {
        if window.usedPercent > 0, window.usedPercent < 0.1 {
            return "<0.1%"
        }
        if window.usedPercent > 0, window.usedPercent < 1 {
            return String(format: "%.1f%%", window.usedPercent)
        }
        return "\(Int(window.usedPercent))%"
    }

    static func percentageText(for reading: UsageReading) -> String? {
        guard reading.status == .live, let window = reading.outerRingWindow else { return nil }
        return percentageText(for: window)
    }

    static func accessibilityText(for window: UsageWindow) -> String {
        "\(percentageText(for: window)) used"
    }

    private var helpText: String {
        switch reading.status {
        case .needsAuth:
            return "\(reading.label): sign in required"
        case .error(let error):
            return "\(reading.label): \(error)"
        case .unknown:
            return "\(reading.label): \(reading.error ?? "no finite allowance reported")"
        case .live:
            guard let window = reading.outerRingWindow else { return "\(reading.label): no reading" }
            return "\(reading.label): \(Self.accessibilityText(for: window)) in \(window.label)"
        }
    }
}

enum UsageBand {
    case ample, watch, critical, exhausted, unknown

    static func band(for fraction: Double) -> UsageBand {
        switch fraction {
        case ..<0.50: return .ample
        case ..<0.70: return .watch
        case ..<1.00: return .critical
        default: return .exhausted
        }
    }

    var color: Color {
        switch self {
        case .ample: return Palette.ample
        case .watch: return Palette.watch
        case .critical, .exhausted: return Palette.critical
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
        case "copilot": return .copilot
        case "grok": return .grok
        case "gemini", "antigravity": return .antigravity
        case "opencode": return .opencode
        case "zcode": return .glm
        case "devin": return .devin
        case "cubic": return .cubic
        default: return nil
        }
    }
}
