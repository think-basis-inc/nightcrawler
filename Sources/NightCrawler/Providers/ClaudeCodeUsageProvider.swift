import Foundation

/// Reads Claude Code usage using the credential file when present and local CLI /usage fallback,
/// not macOS Keychain.
struct ClaudeCodeUsageProvider: UsageProvider {
    let id = "claude"
    let label = "Claude Code"

    typealias SessionDataLoader = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    typealias CLIWindowsReader = @Sendable () async -> [UsageWindow]

    private let credentials: ClaudeCredentialStore
    private let localUsage: ClaudeLocalUsageCache
    private let cliUsage: ClaudeCLIUsageClient
    private let sessionDataLoader: SessionDataLoader
    private let cliWindowsReader: CLIWindowsReader?

    init(
        credentials: ClaudeCredentialStore = .shared,
        localUsage: ClaudeLocalUsageCache = .shared,
        cliUsage: ClaudeCLIUsageClient = ClaudeCLIUsageClient(),
        sessionDataLoader: SessionDataLoader? = nil,
        cliWindowsReader: CLIWindowsReader? = nil
    ) {
        self.credentials = credentials
        self.localUsage = localUsage
        self.cliUsage = cliUsage
        self.sessionDataLoader = sessionDataLoader ?? { request in
            try await URLSession.shared.data(for: request)
        }
        self.cliWindowsReader = cliWindowsReader
    }

    var isAvailable: Bool { true }

    func read() async -> UsageReading {
        if let cached = readingFromLocalCache(), Self.isFresh(cached) {
            return cached
        }
        guard let token = await credentials.read() else {
            return await readFromCLI()
        }
        let credentials = Credentials(
            accessToken: token,
            accountId: ProviderHelpers.sha256Prefix(token)
        )

        var request = URLRequest(
            url: URL(string: "https://api.anthropic.com/api/oauth/usage")!,
            cachePolicy: .reloadIgnoringLocalCacheData
        )
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await sessionDataLoader(request)
            guard let http = response as? HTTPURLResponse else {
                return makeReading(status: .error("Bad response"))
            }
            if http.statusCode == 401 || http.statusCode == 403 {
                return await readFromLocalOrCLI()
            }
            if http.statusCode == 429 {
                if let cached = readingFromLocalCache() { return cached }
                return makeReading(status: .error("Rate limited by Claude"))
            }
            guard http.statusCode == 200 else {
                return makeReading(status: .error("Claude returned \(http.statusCode)"))
            }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let payload = try decoder.decode(UsageResponse.self, from: data)
            var windows = payload.windows()
            if !windows.isEmpty, !windows.contains(where: { $0.id == "fable" || $0.id == "weekly_scoped" }) {
                let cliWindows = await readCLIWindows()
                windows = Self.augment(oauthWindows: windows, with: cliWindows)
            }
            let status: UsageReading.ReadingStatus = windows.isEmpty
                ? .error("Claude returned incomplete usage windows")
                : .live
            return UsageReading(
                providerId: id,
                label: label,
                accountId: credentials.accountId,
                authMode: windows.isEmpty ? "unknown" : "subscription",
                source: "claude_oauth_usage",
                windows: windows,
                status: status,
                observedAt: Date(),
                error: nil
            )
        } catch {
            if let cached = readingFromLocalCache() { return cached }
            return makeReading(status: .error("Claude usage request failed"))
        }
    }

    private func readCLIWindows() async -> [UsageWindow] {
        if let cliWindowsReader {
            return await cliWindowsReader()
        }
        return await cliUsage.readWindows()
    }

    private func readFromLocalOrCLI() async -> UsageReading {
        if let cached = readingFromLocalCache() { return cached }
        return await readFromCLI()
    }

    private static func isFresh(_ reading: UsageReading, now: Date = Date()) -> Bool {
        guard let observedAt = reading.observedAt else { return false }
        let age = now.timeIntervalSince(observedAt)
        return age <= CapacitySnapshot.liveFreshnessInterval && age >= -120
    }

    private func readingFromLocalCache() -> UsageReading? {
        let windows = localUsage.windows()
        guard !windows.isEmpty else { return nil }
        return UsageReading(
            providerId: id,
            label: label,
            accountId: nil,
            authMode: "subscription",
            source: "claude_local_cache",
            windows: windows,
            status: .live,
            observedAt: windows.compactMap(\.observedAt).max() ?? Date(),
            error: nil
        )
    }

    private func readFromCLI() async -> UsageReading {
        let windows = await readCLIWindows()
        guard !windows.isEmpty else {
            if let cached = readingFromLocalCache() { return cached }
            return makeReading(
                status: .needsAuth,
                error: "Open Claude Code once so NightCrawler can read subscription usage"
            )
        }
        return UsageReading(
            providerId: id,
            label: label,
            accountId: nil,
            authMode: "subscription",
            source: "claude_cli_usage",
            windows: windows,
            status: .live,
            observedAt: Date(),
            error: nil
        )
    }

    static func augment(oauthWindows: [UsageWindow], with cliWindows: [UsageWindow]) -> [UsageWindow] {
        guard !oauthWindows.contains(where: { $0.id == "fable" || $0.id == "weekly_scoped" }),
              let fable = cliWindows.first(where: { $0.id == "fable" || $0.id == "weekly_scoped" })
        else {
            return oauthWindows
        }
        var combined = oauthWindows
        combined.append(fable)
        return combined
    }

    private func makeReading(status: UsageReading.ReadingStatus, error: String? = nil) -> UsageReading {
        UsageReading(
            providerId: id,
            label: label,
            accountId: nil,
            authMode: "unknown",
            source: "claude_oauth_usage",
            windows: [],
            status: status,
            observedAt: nil,
            error: error
        )
    }

    private struct Credentials {
        let accessToken: String
        let accountId: String
    }

    private struct UsageResponse: Decodable {
        struct Limit: Decodable {
            let kind: String
            let percent: Double?
            let resetsAt: String?
        }

        struct Window: Decodable {
            let utilization: Double?
            let resetsAt: String?
        }

        let limits: [Limit]?
        let fiveHour: Window?
        let sevenDay: Window?
        let sevenDayOpus: Window?
        let sevenDaySonnet: Window?

        func windows() -> [UsageWindow] {
            var collected: [String: UsageWindow] = [:]

            for limit in limits ?? [] {
                guard let percent = limit.percent,
                      let resetsAt = ProviderHelpers.parseISO8601(limit.resetsAt)
                else { continue }
                let window = UsageWindow(
                    id: limit.kind,
                    label: label(for: limit.kind),
                    used: Int(percent * 100),
                    limit: 10000,
                    usedPercent: percent,
                    windowMinutes: windowMinutes(for: limit.kind),
                    resetsAt: resetsAt
                )
                collected[limit.kind] = window
            }

            merge(window: fiveHour, id: "session", label: "Current session", into: &collected)
            merge(window: sevenDay, id: "weekly_all", label: "All models", into: &collected)
            merge(window: sevenDayOpus, id: "weekly_opus", label: "Opus weekly", into: &collected)
            merge(window: sevenDaySonnet, id: "weekly_sonnet", label: "Sonnet weekly", into: &collected)

            return collected.values.sorted {
                rank($0.id) < rank($1.id)
            }
        }

        private func merge(window: Window?, id: String, label: String, into collected: inout [String: UsageWindow]) {
            guard collected[id] == nil,
                  let window,
                  let percent = window.utilization,
                  let resetsAt = ProviderHelpers.parseISO8601(window.resetsAt)
            else { return }
            collected[id] = UsageWindow(
                id: id,
                label: label,
                used: Int(percent * 100),
                limit: 10000,
                usedPercent: percent,
                windowMinutes: windowMinutes(for: id),
                resetsAt: resetsAt
            )
        }

        private func rank(_ id: String) -> Int {
            switch id {
            case "session": return 0
            case "weekly_all": return 1
            default: return 2
            }
        }

        private func label(for kind: String) -> String {
            ClaudeUsageLabels.label(for: kind)
        }

        private func windowMinutes(for kind: String) -> Int? {
            kind == "session" ? 300 : (kind.hasPrefix("weekly_") ? 10080 : nil)
        }
    }
}
