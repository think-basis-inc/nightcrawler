import SwiftUI

struct PopoverView: View {
    @EnvironmentObject var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("NightCrawler")
                .font(.headline)

            if store.readings.isEmpty {
                Text("No providers enabled or connected.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.readings) { reading in
                    ReadingRow(reading: reading)
                }
            }

            Divider()

            Button("Refresh now") {
                Task { await store.refresh() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding()
        .frame(width: 280)
    }
}

struct ReadingRow: View {
    let reading: UsageReading

    var body: some View {
        HStack {
            RingView(fraction: reading.fraction, color: statusColor)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(reading.label)
                    .font(.system(size: 12, weight: .semibold))
                if reading.status.isError {
                    Text(reading.status == .needsAuth ? "Sign in required" : "Error")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(reading.used) / \(reading.limit) \(reading.windowName)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if !reading.status.isError {
                Text("\(Int(reading.percentUsed))%")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(statusColor)
            }
        }
    }

    private var statusColor: Color {
        switch reading.status {
        case .ok: return .green
        case .warning: return .orange
        case .critical: return .red
        case .needsAuth, .error: return .gray
        }
    }
}
