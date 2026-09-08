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
    @Published private(set) var copilotPlanLimit: Int {
        didSet { defaults.set(copilotPlanLimit, forKey: CopilotPlanSettings.key) }
    }

    private let providers: [UsageProvider]
    private let defaults: UserDefaults
    private let claudeCredentials: ClaudeCredentialStore
    private var timer: Timer?
    private var isPolling = false
    private var demoReadings: [UsageReading]?
    private var deniedProviderIds: Set<String> = []
    private var keychainProviderIds: Set<String> = ["antigravity"]

    private let enabledDefaultsKey = "enabledProviderIds"
    private let orderDefaultsKey = "providerOrder"
    private let routingToolsDefaultsKey = "routingToolStates"

    init(
        providers: [UsageProvider] = UsageStore.defaultProviders(),
        defaults: UserDefaults = .standard,
        claudeCredentials: ClaudeCredentialStore = .shared
    ) {
        self.providers = providers
        self.defaults = defaults
        self.claudeCredentials = claudeCredentials
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
        self.copilotPlanLimit = CopilotPlanSettings.current(defaults: defaults)
        self.readings = PersistedReadingCache.load(
            defaults: defaults,
            knownProviderIds: Set(providerIds)
        )
    }

    var providerCatalog: [ProviderCatalogItem] {
        providerOrder.compactMap { id in
            providers.first(where: { $0.id == id }).map {
                ProviderCatalogItem(id: $0.id, label: $0.label)
            }
        }
    }

    var orderedReadings: [UsageReading] {
        let visible = readings.filter { isProviderEnabled($0.providerId) }
        let visibleIds = Set(visible.map(\.providerId))
        let placeholders = routingToolStates
            .filter { $0.enabled && !visibleIds.contains($0.id) }
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
        return (visible + placeholders).sorted(by: readingComesBefore)
    }

    func isProviderEnabled(_ providerId: String) -> Bool {
        routingToolStates.first(where: { $0.id == providerId })?.enabled
            ?? enabledProviderIds.contains(providerId)
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
        await poll()
    }

    func refresh(providerId: String) async {
        if let demoReading = demoReadings?.first(where: { $0.providerId == providerId }) {
            updateReading(demoReading)
            return
        }
        deniedProviderIds.remove(providerId)
        if providerId == "claude" {
            await claudeCredentials.allowRetry()
        }
        guard let provider = providers.first(where: { $0.id == providerId }) else { return }
        let reading = await provider.read()
        updateReading(reading)
        if case .needsAuth = reading.status, keychainProviderIds.contains(providerId) {
            deniedProviderIds.insert(providerId)
        }
    }

    func toggle(providerId: String) {
        if routingToolStates.contains(where: { $0.id == providerId }) {
            toggleRoutingTool(providerId)
            return
        }
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
        if routingToolStates[index].enabled {
            deniedProviderIds.remove(id)
            if let demoReading = demoReadings?.first(where: { $0.providerId == id }) {
                updateReading(demoReading)
            } else {
                Task { await refresh(providerId: id) }
            }
        } else {
            readings.removeAll { $0.providerId == id }
        }
    }

    func toggleRoutingToolAvailability(_ id: String) {
        guard let index = routingToolStates.firstIndex(where: { $0.id == id }) else { return }
        routingToolStates[index].available.toggle()
    }

    func setCopilotPlanLimit(_ limit: Int) {
        guard CopilotPlanSettings.allowedLimits.contains(limit), limit != copilotPlanLimit else { return }
        copilotPlanLimit = limit
        Task { await refresh(providerId: "copilot") }
    }

    func poll() async {
        guard !isPolling else { return }
        isPolling = true
        defer { isPolling = false }
        await claudeCredentials.allowRetry()
        let enabled = providers.filter { isProviderEnabled($0.id) && !deniedProviderIds.contains($0.id) }
        await withTaskGroup(of: UsageReading.self) { group in
            for provider in enabled {
                group.addTask { await provider.read() }
            }
            for await reading in group {
                updateReading(reading)
                if case .needsAuth = reading.status,
                   keychainProviderIds.contains(reading.providerId),
                   readings.first(where: { $0.providerId == reading.providerId })?.windows.isEmpty != false {
                    deniedProviderIds.insert(reading.providerId)
                }
            }
        }
        ensurePlaceholders()
        readings.sort(by: readingComesBefore)
    }

    private func updateReading(_ incoming: UsageReading) {
        let reading = UsageReading(
            providerId: incoming.providerId,
            label: incoming.label,
            accountId: incoming.accountId,
            authMode: incoming.authMode,
            source: incoming.source,
            windows: incoming.windows.map { $0.observed(at: incoming.observedAt) },
            status: incoming.status,
            observedAt: incoming.observedAt,
            error: incoming.error
        )
        if let index = readings.firstIndex(where: { $0.providerId == reading.providerId }) {
            let previous = readings[index]
            if reading.status != .live, previous.status == .live, !previous.windows.isEmpty {
                let observedAt = previous.observedAt ?? .distantPast
                let remainsLive = Date().timeIntervalSince(observedAt) <= CapacitySnapshot.liveFreshnessInterval
                readings[index] = UsageReading(
                    providerId: previous.providerId,
                    label: previous.label,
                    accountId: previous.accountId,
                    authMode: previous.authMode,
                    source: previous.source,
                    windows: previous.windows,
                    status: remainsLive ? .live : reading.status,
                    observedAt: previous.observedAt,
                    error: reading.error.map { "Latest refresh failed: \($0)" }
                )
                return
            }
            if reading.providerId == "claude",
               previous.status == .live,
               let priorFable = previous.windows.first(where: { $0.id == "fable" || $0.id == "weekly_scoped" }),
               let priorFableObservedAt = priorFable.observedAt ?? previous.observedAt,
               Date().timeIntervalSince(priorFableObservedAt) <= PersistedReadingCache.maxAge,
               !reading.windows.contains(where: { $0.id == "fable" || $0.id == "weekly_scoped" }) {
                var mergedWindows = reading.windows
                mergedWindows.append(priorFable.observed(at: priorFableObservedAt))
                readings[index] = UsageReading(
                    providerId: reading.providerId,
                    label: reading.label,
                    accountId: reading.accountId ?? previous.accountId,
                    authMode: reading.authMode,
                    source: reading.source,
                    windows: mergedWindows,
                    status: reading.status,
                    observedAt: reading.observedAt ?? previous.observedAt,
                    error: reading.error
                )
                if reading.status == .live, !mergedWindows.isEmpty {
                    PersistedReadingCache.save(readings, defaults: defaults)
                }
                return
            }
            readings[index] = reading
        } else {
            readings.append(reading)
        }
        if reading.status == .live, !reading.windows.isEmpty {
            PersistedReadingCache.save(readings, defaults: defaults)
        }
    }

    private func ensurePlaceholders() {
        for provider in providers where isProviderEnabled(provider.id) {
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
        let lhsRank = rank(for: lhs.providerId)
        let rhsRank = rank(for: rhs.providerId)
        if lhsRank != rhsRank { return lhsRank < rhsRank }
        return lhs.label < rhs.label
    }

    private func rank(for providerId: String) -> Int {
        if let rank = providerOrder.firstIndex(of: providerId) { return rank }
        if let rank = routingToolStates.firstIndex(where: { $0.id == providerId }) {
            return providerOrder.count + rank
        }
        return providerOrder.count + routingToolStates.count
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
            DinoCacheUsageProvider(id: "devin", label: "Devin"),
            DinoCacheUsageProvider(id: "cubic", label: "Cubic"),
            GeminiUsageProvider(),
            OpenCodeUsageProvider(),
            AntigravityUsageProvider(),
            ZCodeUsageProvider(),
        ]
    }
}
