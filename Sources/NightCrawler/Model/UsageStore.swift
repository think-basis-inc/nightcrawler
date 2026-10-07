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
    @Published private(set) var cubicUsageRepository: String

    private let providers: [UsageProvider]
    private let defaults: UserDefaults
    private let claudeCredentials: ClaudeCredentialStore
    private let providerReadBudget: TimeInterval
    private var timer: Timer?
    private var cursorTimer: Timer?
    private var isPolling = false
    private var queuedPoll = false
    private var demoReadings: [UsageReading]?
    private var deniedProviderIds: Set<String> = []
    private var keychainProviderIds: Set<String> = ["antigravity"]
    private var signInWatches: [String: (token: UUID, task: Task<Void, Never>)] = [:]

    private static let enabledDefaultsKey = "enabledProviderIds"
    private static let claudeDefaultEnabledMigrationKey = "migratedDefaultEnabledClaude"
    private static let grokBotDefaultEnabledMigrationKey = "migratedDefaultEnabledGrokBot"
    private let orderDefaultsKey = "providerOrder"
    private let routingToolsDefaultsKey = "routingToolStates"
    private static let defaultEnabledProviderIds: Set<String> = [
        "claude", "codex", "cursor", "grokbot", "grok", "opencode", "zcode",
    ]

    init(
        providers: [UsageProvider] = UsageStore.defaultProviders(),
        defaults: UserDefaults = .standard,
        claudeCredentials: ClaudeCredentialStore = .shared,
        providerReadBudget: TimeInterval = 20
    ) {
        self.providers = providers
        self.defaults = defaults
        self.claudeCredentials = claudeCredentials
        self.providerReadBudget = providerReadBudget
        let providerIds = providers.map(\.id)
        Self.migrateClaudeDefaultEnabled(defaults: defaults)
        Self.migrateGrokBotDefaultEnabled(defaults: defaults)
        let saved = defaults.array(forKey: Self.enabledDefaultsKey) as? [String]
        self.enabledProviderIds = saved.map(Set.init) ?? Self.defaultEnabledProviderIds
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
        self.cubicUsageRepository = defaults.string(forKey: CubicUsageProvider.repositoryKey) ?? ""
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
        startCursorRefreshTimer()
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
        cursorTimer?.invalidate()
        cursorTimer = nil
    }

    private func startCursorRefreshTimer() {
        cursorTimer?.invalidate()
        cursorTimer = nil
        guard demoReadings == nil, isProviderEnabled("cursor") else { return }
        cursorTimer = Timer.scheduledTimer(
            withTimeInterval: CursorUsageProvider.liveRefreshInterval,
            repeats: true
        ) { [weak self] _ in
            Task { await self?.refresh(providerId: "cursor") }
        }
    }

    func setCubicUsageRepository(_ repository: String) {
        let value = repository.trimmingCharacters(in: .whitespacesAndNewlines)
        guard CubicUsageProvider.validRepository(value), value != cubicUsageRepository else { return }
        cubicUsageRepository = value
        defaults.set(value, forKey: CubicUsageProvider.repositoryKey)
        // An allowance from another organization must not survive a source change.
        readings.removeAll { $0.providerId == "cubic" }
        PersistedReadingCache.save(readings, defaults: defaults)
        if isProviderEnabled("cubic") { Task { await refresh(providerId: "cubic") } }
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
        let cubicSource = cubicUsageRepository
        let reading = await Self.readWithBudget(provider, budget: providerReadBudget)
        guard providerId != "cubic" || cubicSource == cubicUsageRepository else { return }
        guard isProviderEnabled(providerId) else { return }
        updateReading(reading)
        if reading.source == UsageReading.keychainDeniedSource, keychainProviderIds.contains(providerId) {
            deniedProviderIds.insert(providerId)
        }
    }

    /// Re-reads a provider while the user finishes signing in elsewhere, so the
    /// ring returns as soon as the tool saves its credentials instead of on
    /// the next minute-long poll. Stops at the first reading that is no longer
    /// signed out or failing transiently, after `attempts`, or when the
    /// provider is switched off. A denied keychain prompt is neither, so the
    /// watch never raises that system dialog again by itself.
    func watchSignIn(
        providerId: String,
        interval: Duration = .seconds(5),
        attempts: Int = 60
    ) {
        signInWatches[providerId]?.task.cancel()
        let token = UUID()
        let task = Task { [weak self] in
            for _ in 0..<attempts {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled, let self else { return }
                guard self.isProviderEnabled(providerId) else { break }
                await self.refresh(providerId: providerId)
                guard !Task.isCancelled else { return }
                guard let reading = self.readings.first(where: { $0.providerId == providerId }) else { break }
                let stillWaiting: Bool
                if case .error = reading.status { stillWaiting = true } else { stillWaiting = reading.isSignedOut }
                if !stillWaiting { break }
            }
            if self?.signInWatches[providerId]?.token == token {
                self?.signInWatches[providerId] = nil
            }
        }
        signInWatches[providerId] = (token, task)
    }

    private func cancelSignInWatch(_ providerId: String) {
        signInWatches.removeValue(forKey: providerId)?.task.cancel()
    }

    func toggle(providerId: String) {
        if routingToolStates.contains(where: { $0.id == providerId }) {
            toggleRoutingTool(providerId)
            return
        }
        if enabledProviderIds.contains(providerId) {
            enabledProviderIds.remove(providerId)
            cancelSignInWatch(providerId)
            readings.removeAll { $0.providerId == providerId }
        } else {
            enabledProviderIds.insert(providerId)
            deniedProviderIds.remove(providerId)
            ensurePlaceholders()
            if let demoReading = demoReadings?.first(where: { $0.providerId == providerId }) {
                updateReading(demoReading)
            } else {
                Task { await refresh(providerId: providerId) }
            }
        }
        if providerId == "cursor" { startCursorRefreshTimer() }
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
            cancelSignInWatch(id)
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
        if isPolling {
            queuedPoll = true
            return
        }
        repeat {
            queuedPoll = false
            isPolling = true
            defer { isPolling = false }
            await runPoll()
        } while queuedPoll
    }

    private func runPoll() async {
        let cubicSource = cubicUsageRepository
        await claudeCredentials.allowRetry()
        let enabled = providers.filter { isProviderEnabled($0.id) && !deniedProviderIds.contains($0.id) }
        await withTaskGroup(of: UsageReading.self) { group in
            for provider in enabled {
                let budget = providerReadBudget
                group.addTask {
                    await Self.readWithBudget(provider, budget: budget)
                }
            }
            for await reading in group {
                if reading.providerId == "cubic", cubicSource != cubicUsageRepository { continue }
                updateReading(reading)
                if reading.source == UsageReading.keychainDeniedSource,
                   keychainProviderIds.contains(reading.providerId) {
                    deniedProviderIds.insert(reading.providerId)
                }
            }
        }
        ensurePlaceholders()
        readings.sort(by: readingComesBefore)
    }

    nonisolated private static func readWithBudget(_ provider: UsageProvider, budget: TimeInterval) async -> UsageReading {
        await withCheckedContinuation { continuation in
            let gate = OnceGate()
            Task {
                let reading = await provider.read()
                gate.go { continuation.resume(returning: reading) }
            }
            Task {
                try? await Task.sleep(for: .seconds(max(budget, 0.05)))
                gate.go {
                    continuation.resume(returning: timeoutReading(for: provider))
                }
            }
        }
    }

    nonisolated private static func timeoutReading(for provider: UsageProvider) -> UsageReading {
        UsageReading(
            providerId: provider.id,
            label: provider.label,
            accountId: nil,
            authMode: "unknown",
            source: "timeout",
            windows: [],
            status: .error("Usage refresh timed out"),
            observedAt: nil,
            error: "Usage refresh timed out"
        )
    }

    private static func isTransientRefreshFailure(_ status: UsageReading.ReadingStatus) -> Bool {
        switch status {
        case .error, .needsAuth: return true
        case .live, .unknown: return false
        }
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
            if Self.isTransientRefreshFailure(reading.status),
               previous.status == .live,
               !previous.windows.isEmpty {
                let remainsLive = previous.isFreshlyObserved()
                // Keep denials recognizable even while cached usage is live,
                // so an explicit icon click can retry the paused provider.
                let keepsDenial = reading.source == UsageReading.keychainDeniedSource
                readings[index] = UsageReading(
                    providerId: previous.providerId,
                    label: previous.label,
                    accountId: previous.accountId,
                    authMode: previous.authMode,
                    source: keepsDenial ? reading.source : previous.source,
                    windows: previous.windows,
                    status: remainsLive ? .live : reading.status,
                    observedAt: previous.observedAt,
                    error: reading.error.map { "Latest refresh failed: \($0)" }
                )
                return
            }
            if previous.status == .live,
               let keepers = Self.limitWindowKeepers(for: reading.providerId) {
                let mergedWindows = Self.carryForwardLimitWindows(
                    from: previous,
                    into: reading.windows,
                    keepers: keepers
                )
                if mergedWindows != reading.windows {
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
            }
            readings[index] = reading
        } else {
            readings.append(reading)
        }
        if reading.status == .live, !reading.windows.isEmpty {
            PersistedReadingCache.save(readings, defaults: defaults)
        }
    }

    private static func limitWindowKeepers(for providerId: String) -> [[String]]? {
        switch providerId {
        case "claude":
            return [["weekly_all"], ["fable", "weekly_scoped"]]
        case "cursor":
            return [["included", "auto", "cursor_models"], ["api", "other_models"]]
        default:
            return nil
        }
    }

    private static func carryForwardLimitWindows(
        from previous: UsageReading,
        into incoming: [UsageWindow],
        keepers: [[String]],
        now: Date = Date()
    ) -> [UsageWindow] {
        var merged = incoming
        for ids in keepers {
            guard !merged.contains(where: { ids.contains($0.id) }) else { continue }
            guard let prior = previous.windows.first(where: { ids.contains($0.id) }) else { continue }
            if let resetsAt = prior.resetsAt, resetsAt <= now { continue }
            let observedAt = prior.observedAt ?? previous.observedAt
            if let observedAt, now.timeIntervalSince(observedAt) > PersistedReadingCache.maxAge {
                continue
            }
            merged.append(prior.observed(at: observedAt))
        }
        return merged
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
                        source: UsageReading.pendingSource,
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
        defaults.set(Array(enabledProviderIds), forKey: Self.enabledDefaultsKey)
    }

    private static func migrateClaudeDefaultEnabled(defaults: UserDefaults) {
        guard !defaults.bool(forKey: claudeDefaultEnabledMigrationKey) else { return }
        defaults.set(true, forKey: claudeDefaultEnabledMigrationKey)
        guard var ids = defaults.array(forKey: enabledDefaultsKey) as? [String],
              !ids.contains("claude")
        else { return }
        ids.append("claude")
        defaults.set(ids, forKey: enabledDefaultsKey)
    }

    private static func migrateGrokBotDefaultEnabled(defaults: UserDefaults) {
        guard !defaults.bool(forKey: grokBotDefaultEnabledMigrationKey) else { return }
        defaults.set(true, forKey: grokBotDefaultEnabledMigrationKey)
        guard var ids = defaults.array(forKey: enabledDefaultsKey) as? [String],
              !ids.contains("grokbot")
        else { return }
        ids.append("grokbot")
        defaults.set(ids, forKey: enabledDefaultsKey)
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
            GrokBotUsageProvider(),
            GitHubCopilotUsageProvider(),
            GrokUsageProvider(),
            DevinUsageProvider(),
            CubicUsageProvider(),
            GeminiUsageProvider(),
            OpenCodeUsageProvider(),
            AntigravityUsageProvider(),
            ZCodeUsageProvider(),
        ]
    }
}

private final class OnceGate: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func go(_ body: () -> Void) {
        lock.lock()
        if done {
            lock.unlock()
            return
        }
        done = true
        lock.unlock()
        body()
    }
}
