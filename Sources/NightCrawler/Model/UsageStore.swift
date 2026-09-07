import Combine
import Foundation

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var readings: [UsageReading] = []
    @Published var enabledProviderIds: Set<String> = [
        "claude", "codex", "cursor", "copilot", "grok", "gemini", "opencode", "antigravity", "zcode"
    ]

    private let providers: [UsageProvider]
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
        let enabled = providers.filter { enabledProviderIds.contains($0.id) && $0.isAvailable }
        let next = await withTaskGroup(of: UsageReading.self) { group in
            for provider in enabled {
                group.addTask { await provider.read() }
            }
            var collected: [UsageReading] = []
            for await reading in group {
                collected.append(reading)
            }
            return collected
        }
        readings = next.sorted { $0.label < $1.label }
    }

    static func defaultProviders() -> [UsageProvider] {
        [
            ClaudeCodeUsageProvider(),
            CodexCLIUsageProvider(),
            CursorUsageProvider(),
            GitHubCopilotUsageProvider(),
            GrokUsageProvider(),
            GeminiUsageProvider(),
            OpenCodeUsageProvider(),
            AntigravityUsageProvider(),
            ZCodeUsageProvider(),
        ]
    }
}
