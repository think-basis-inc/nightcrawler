import SwiftUI

struct HUDView: View {
    @EnvironmentObject var store: UsageStore

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(store.readings) { reading in
                    ProviderIcon(reading: reading)
                }
            }
            .padding(10)
        }
        .frame(width: 60)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Material.ultraThin)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
        )
    }
}

struct ProviderIcon: View {
    let reading: UsageReading
    @State private var isHovered = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.25))
                .frame(width: 38, height: 38)

            RingView(fraction: reading.status.isError ? 0 : reading.fraction, color: statusColor)
                .frame(width: 38, height: 38)

            Text(initials)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.primary)
        }
        .frame(width: 40, height: 40)
        .scaleEffect(isHovered ? 1.08 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isHovered)
        .onHover { isHovered in
            self.isHovered = isHovered
        }
        .help(helpText)
    }

    private var initials: String {
        let words = reading.label.components(separatedBy: .whitespacesAndNewlines)
        let chars = words.compactMap { $0.first }
        return String(chars.prefix(2)).uppercased()
    }

    private var statusColor: Color {
        switch reading.status {
        case .ok: return .green
        case .warning: return .orange
        case .critical: return .red
        case .needsAuth, .error: return .gray
        }
    }

    private var helpText: String {
        if reading.status.isError {
            return "\(reading.label): \(reading.status == .needsAuth ? "sign in required" : "error")"
        }
        return "\(reading.label): \(Int(reading.percentUsed))% of \(reading.limit)"
    }
}
