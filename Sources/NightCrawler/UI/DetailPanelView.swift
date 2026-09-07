import SwiftUI

struct DetailPanelView: View {
    let reading: UsageReading
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(reading.label)
                    .font(.headline)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }

            if reading.status.isError {
                Text(statusMessage)
                    .foregroundStyle(.secondary)
            } else if reading.windows.isEmpty {
                Text("No usage windows reported.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(reading.windows) { window in
                        WindowRow(window: window)
                    }
                }
            }

            if let observedAt = reading.observedAt {
                HStack {
                    Spacer()
                    Text("Updated \(relativeTime(observedAt))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .frame(width: 260)
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

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct WindowRow: View {
    let window: UsageWindow

    var body: some View {
        HStack(spacing: 12) {
            RingView(fraction: window.fraction, color: statusColor)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(window.label)
                    .font(.system(size: 12, weight: .semibold))
                Text("\(window.used) / \(window.limit)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let resetsAt = window.resetsAt {
                    Text("Resets \(relativeTime(resetsAt))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text("\(Int(window.usedPercent))%")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(statusColor)
        }
    }

    private var statusColor: Color {
        switch window.status {
        case .ok: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
