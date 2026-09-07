import Combine
import Foundation

@MainActor
final class UsageStore: ObservableObject {
    @Published var readings: [UsageReading] = []
    @Published var enabledProviderIds: Set<String> {
        didSet { saveEnabled() }
    }
    @Published private(set) var providerOrder: [String] {
        didSet { saveProviderOrder() }
    }
    @Published private(set) var routingToolStates: [RoutingToolState] {
        didSet { saveRoutingToolStates() }
    }

    private let providers: [UsageProvider]
    private let defaults: UserDefaults
    private var timer: Timer?
    private var demoReadings: [UsageReading]?
    private var deniedProviderIds: Set<String> = []
    private var keychainProviderIds: Set<String> = ["claude", "copilot", "antigravity"]

    private let enabledDefaultsKey = "enabledProviderIds"
    private let orderDefaultsKey = "providerOrder"
    private let routingToolsDefaultsKey = "routingToolStates"

    init(
        providers: [UsageProvider] = UsageStore.defaultProviders(),
        defaults: UserDefaults = .standard
    ) {
        self.providers = providers
        self.defaults = defaults
        let providerIds = providers.map(\.id)
        let saved = defaults.array(forKey: enabledDefaultsKey) as? [String]
        let defaultEnabled: Set<String> = ["codex", "cursor", "grok", "opencode", "zcode"]
        self.enabledProviderIds = saved.map(Set.init) ?? defaultEnabled
        self.providerOrder = Self.normalizedOrder(
            defaults.array(forKey: orderDefaultsKey) as? [String],
            providerIds: providerIds
        )
        if let data = defaults.data(forKey: routingToolsDefaultsKey),
           let decoded = try? JSONDecoder().decode([RoutingToolState].self, from: data) {
            self.routingToolStates = Self.normalizedRoutingTools(decoded)
        } else {
            self.routingToolStates = RoutingToolState.defaults
        }
    }

    var providerCatalog: [ProviderCatalogItem] {
        providerOrder.compactMap { id in
            providers.first(where: { $0.id == id }).map {
                ProviderCatalogItem(id: $0.id, label: $0.label)
            }
        }
    }

    var orderedReadings: [UsageReading] {
        let providerReadings = readings
            .filter { enabledProviderIds.contains($0.providerId) }
            .sorted(by: readingComesBefore)
        let routingReadings = routingToolStates
            .filter(\.enabled)
            .map { tool in
                UsageReading(
                    providerId: tool.id,
                    label: tool.label,
                    accountId: nil,
                    authMode: "none",
                    source: "routing_state",
                    windows: [],
                    status: tool.available
                        ? .unknown
                        : .error("Currently unavailable"),
                    observedAt: nil,
                    error: tool.available
                        ? "Available; no finite quota is reported"
                        : "Currently unavailable"
                )
            }
        return providerReadings + routingReadings
    }

    func startPolling(interval: TimeInterval = 60, skipInitialPoll: Bool = false) {
        guard demoReadings == nil, timer == nil else { return }
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
        if let demoReadings {
            readings = demoReadings
            return
        }
        deniedProviderIds.removeAll()
        await ClaudeCredentialStore.shared.allowRetry()
        await poll()
    }

    func refresh(providerId: String) async {
        if let demoReading = demoReadings?.first(where: { $0.providerId == providerId }) {
            updateReading(demoReading)
            return
        }
        deniedProviderIds.remove(providerId)
        if providerId == "claude" {
            await ClaudeCredentialStore.shared.allowRetry()
        }
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
            if let demoReading = demoReadings?.first(where: { $0.providerId == providerId }) {
                updateReading(demoReading)
            } else {
                Task { await refresh(providerId: providerId) }
            }
        }
    }

    func setDemoMode(_ enabled: Bool, readings: [UsageReading] = DemoData.readings) {
        stopPolling()
        if enabled {
            demoReadings = readings
            self.readings = readings
        } else {
            demoReadings = nil
            self.readings = []
        }
    }

    func moveProvider(_ providerId: String, by offset: Int) {
        guard offset != 0,
              let source = providerOrder.firstIndex(of: providerId)
        else { return }
        let destination = min(max(source + offset, 0), providerOrder.count - 1)
        guard source != destination else { return }
        providerOrder.remove(at: source)
        providerOrder.insert(providerId, at: destination)
    }

    func toggleRoutingTool(_ id: String) {
        guard let index = routingToolStates.firstIndex(where: { $0.id == id }) else { return }
        routingToolStates[index].enabled.toggle()
    }

    func toggleRoutingToolAvailability(_ id: String) {
        guard let index = routingToolStates.firstIndex(where: { $0.id == id }) else { return }
        routingToolStates[index].available.toggle()
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
        readings.sort(by: readingComesBefore)
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
        defaults.set(Array(enabledProviderIds), forKey: enabledDefaultsKey)
    }

    private func saveProviderOrder() {
        defaults.set(providerOrder, forKey: orderDefaultsKey)
    }

    private func saveRoutingToolStates() {
        guard let data = try? JSONEncoder().encode(routingToolStates) else { return }
        defaults.set(data, forKey: routingToolsDefaultsKey)
    }

    private func readingComesBefore(_ lhs: UsageReading, _ rhs: UsageReading) -> Bool {
        let lhsRank = providerOrder.firstIndex(of: lhs.providerId) ?? providerOrder.count
        let rhsRank = providerOrder.firstIndex(of: rhs.providerId) ?? providerOrder.count
        if lhsRank != rhsRank { return lhsRank < rhsRank }
        return lhs.label < rhs.label
    }

    private static func normalizedOrder(_ saved: [String]?, providerIds: [String]) -> [String] {
        let known = Set(providerIds)
        var seen: Set<String> = []
        let savedKnown = (saved ?? []).filter { known.contains($0) && seen.insert($0).inserted }
        return savedKnown + providerIds.filter { !savedKnown.contains($0) }
    }

    private static func normalizedRoutingTools(_ saved: [RoutingToolState]) -> [RoutingToolState] {
        let savedById = Dictionary(saved.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return RoutingToolState.defaults.map { savedById[$0.id] ?? $0 }
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
