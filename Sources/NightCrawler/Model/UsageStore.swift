import Combine
import Foundation

@MainActor
final class UsageStore: ObservableObject {
    @Published var readings: [UsageReading] = []
    @Published var enabledProviderIds: Set<String> {
        didSet { saveEnabled() }
    }

    private let providers: [UsageProvider]
    private var timer: Timer?
    private var deniedProviderIds: Set<String> = []
    private var keychainProviderIds: Set<String> = ["claude", "copilot", "antigravity"]

    private let enabledDefaultsKey = "enabledProviderIds"

    init(providers: [UsageProvider] = UsageStore.defaultProviders()) {
        self.providers = providers
        let saved = UserDefaults.standard.array(forKey: enabledDefaultsKey) as? [String]
        let defaultEnabled: Set<String> = ["codex", "cursor", "grok", "opencode", "zcode"]
        self.enabledProviderIds = saved.map(Set.init) ?? defaultEnabled
    }

    func startPolling(interval: TimeInterval = 60, skipInitialPoll: Bool = false) {
        if !skipInitialPoll {
            Task { await poll() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { await self?.poll() }
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() async {
        deniedProviderIds.removeAll()
        await poll()
    }

    func refresh(providerId: String) async {
        deniedProviderIds.remove(providerId)
        guard let provider = providers.first(where: { $0.id == providerId }) else { return }
        let reading = await provider.read()
        updateReading(reading)
        if case .needsAuth = reading.status, keychainProviderIds.contains(providerId) {
            deniedProviderIds.insert(providerId)
        }
    }

    func toggle(providerId: String) {
        if enabledProviderIds.contains(providerId) {
            enabledProviderIds.remove(providerId)
            readings.removeAll { $0.providerId == providerId }
        } else {
            enabledProviderIds.insert(providerId)
            deniedProviderIds.remove(providerId)
            Task { await refresh(providerId: providerId) }
        }
    }

    private func poll() async {
        let enabled = providers.filter { enabledProviderIds.contains($0.id) && !deniedProviderIds.contains($0.id) }
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
        for reading in next {
            updateReading(reading)
            if case .needsAuth = reading.status, keychainProviderIds.contains(reading.providerId) {
                deniedProviderIds.insert(reading.providerId)
            }
        }
        ensurePlaceholders()
        readings.sort { $0.label < $1.label }
    }

    private func updateReading(_ reading: UsageReading) {
        if let index = readings.firstIndex(where: { $0.providerId == reading.providerId }) {
            readings[index] = reading
        } else {
            readings.append(reading)
        }
    }

    private func ensurePlaceholders() {
        for provider in providers where enabledProviderIds.contains(provider.id) {
            if readings.firstIndex(where: { $0.providerId == provider.id }) == nil {
                readings.append(
                    UsageReading(
                        providerId: provider.id,
                        label: provider.label,
                        accountId: nil,
                        authMode: "unknown",
                        source: "pending",
                        windows: [],
                        status: .needsAuth,
                        observedAt: nil,
                        error: deniedProviderIds.contains(provider.id)
                            ? "Keychain access was denied; open Settings to retry"
                            : "Select to refresh"
                    )
                )
            }
        }
    }

    private func saveEnabled() {
        UserDefaults.standard.set(Array(enabledProviderIds), forKey: enabledDefaultsKey)
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
