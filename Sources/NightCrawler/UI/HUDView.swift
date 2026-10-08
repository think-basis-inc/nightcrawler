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

                if reading.isFreshlyObserved(), let outer = reading.outerRingWindow, outer.limit > 0 {
                    usageArc(window: outer, inset: HUDLayout.trackStroke / 2, lineWidth: HUDLayout.progressStroke)
                }

                if reading.isFreshlyObserved(), let inner = reading.innerRingWindow, inner.limit > 0 {
                    usageArc(
                        window: inner,
                        inset: HUDLayout.trackStroke + HUDLayout.progressStroke,
                        lineWidth: HUDLayout.innerProgressStroke
                    )
                }

                if reading.isFreshlyObserved(), let core = reading.thirdRingWindow, core.limit > 0 {
                    usageArc(
                        window: core,
                        inset: HUDLayout.trackStroke + HUDLayout.progressStroke + HUDLayout.innerProgressStroke,
                        lineWidth: HUDLayout.coreProgressStroke
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
        guard let summary = Self.ringSummary(for: reading) else {
            return reading.error ?? "No finite allowance reported"
        }
        return summary
    }

    static func percentageText(for window: UsageWindow) -> String {
        UsagePercentText.display(percent: window.usedPercent, used: window.used, limit: window.limit)
    }

    static func percentageText(for reading: UsageReading, now: Date = Date()) -> String? {
        guard reading.isFreshlyObserved(now: now), let window = reading.outerRingWindow else { return nil }
        return percentageText(for: window)
    }

    static func accessibilityText(for window: UsageWindow) -> String {
        if window.limit <= 0 {
            return "\(window.used) credits used"
        }
        return "\(percentageText(for: window)) used"
    }

    static func ringSummary(for reading: UsageReading, now: Date = Date()) -> String? {
        guard reading.isFreshlyObserved(now: now) else { return nil }
        let rings = [reading.outerRingWindow, reading.innerRingWindow, reading.thirdRingWindow]
            .compactMap { $0 }
        guard !rings.isEmpty else { return nil }
        return rings.map { "\(percentageText(for: $0)) used in \($0.label)" }.joined(separator: ", ")
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
            guard let summary = Self.ringSummary(for: reading) else {
                return "\(reading.label): last reading is stale"
            }
            return "\(reading.label): \(summary)"
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
        case "grokbot": return .grokbot
        case "gemini", "antigravity": return .antigravity
        case "opencode": return .opencode
        case "zcode": return .glm
        case "devin": return .devin
        case "cubic": return .cubic
        default: return nil
        }
    }
}
