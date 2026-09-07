import Combine
import Foundation

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var readings: [UsageReading] = []
    @Published var enabledProviderIds: Set<String> = ["claude", "codex", "copilot"]

    private var providers: [UsageProvider] = []
    private var timer: Timer?

    init(providers: [UsageProvider] = UsageStore.defaultProviders()) {
        self.providers = providers
    }

    func startPolling(interval: TimeInterval = 60) {
        Task { await poll() }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { await self?.poll() }
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() async {
        await poll()
    }

    private func poll() async {
        var next: [UsageReading] = []
        for provider in providers where enabledProviderIds.contains(provider.id) {
            do {
                if let reading = try await provider.read() {
                    next.append(reading)
                }
            } catch {
                next.append(UsageReading(
                    providerId: provider.id,
                    label: provider.label,
                    percentUsed: 0,
                    used: 0,
                    limit: 0,
                    windowName: "",
                    resetsAt: nil,
                    status: .error(error.localizedDescription)
                ))
            }
        }
        readings = next
    }

    static func defaultProviders() -> [UsageProvider] {
        [
            GitHubCopilotUsageProvider()
        ]
    }
}
