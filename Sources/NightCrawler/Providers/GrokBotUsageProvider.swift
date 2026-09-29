import Foundation

/// Weekly Grok Bot allowance from Cursor's Sand usage RPC.
/// Separate from Cursor Models cutoff and from the Grok CLI meter.
struct GrokBotUsageProvider: UsageProvider {
    let id = "grokbot"
    let label = "Grok Bot"

    typealias StoreReader = @Sendable () async -> ProcessRunner.RunResult
    typealias Loader = QuotaHTTP.Loader

    static let usageURL = URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetSandUsageStatus")!

    private let storePath: String
    private let storeReader: StoreReader
    private let loader: Loader
    private let sessionCache: CursorSessionCache

    init(
        storePath: String = CursorUsageProvider.defaultStorePath,
        storeReader: StoreReader? = nil,
        loader: Loader? = nil,
        sessionCache: CursorSessionCache = .shared
    ) {
        self.storePath = storePath
        self.sessionCache = sessionCache
        self.loader = loader ?? QuotaHTTP.load
        self.storeReader = storeReader ?? { [storePath] in
            await ProcessRunner.run(
                command: "/usr/bin/sqlite3",
                arguments: [
                    "-cmd", ".timeout 2000",
                    "-json",
                    storePath,
                    CursorUsageProvider.sessionSQL,
                ],
                timeout: 2.5
            )
        }
    }

    var isAvailable: Bool {
        FileManager.default.fileExists(atPath: storePath)
    }

    func read() async -> UsageReading {
        switch await loadSession(allowCache: true) {
        case .ready(let credentials):
            return await fetchUsage(using: credentials, allowStoreRetry: true)
        case .missingAuth:
            return makeReading(
                status: .needsAuth,
                error: "Supported Cursor editor session unavailable; sign in through Cursor"
            )
        case .unavailable:
            return makeReading(
                status: .error("Cursor editor session store was busy or unreadable")
            )
        }
    }

    static func windows(from root: [String: Any]) -> [UsageWindow]? {
        if root["usesPooledEnterpriseAllowance"] as? Bool == true { return nil }
        if root["hasNonZeroIncludedLimit"] as? Bool == false { return nil }
        if root["includedLimitZero"] as? Bool == true { return nil }
        guard let percent = Self.percent(root["usagePercent"]) else { return nil }
        let start = ProviderHelpers.parseISO8601(root["currentPeriodStart"] as? String)
        let end = ProviderHelpers.parseISO8601(root["nextResetTimestampUtc"] as? String)
        let windowMinutes: Int = {
            if let start, let end, end > start {
                return Int(end.timeIntervalSince(start) / 60)
            }
            return 10_080
        }()
        return [
            UsageWindow(
                id: "weekly",
                label: "Weekly usage",
                used: Int(percent * 100),
                limit: 10_000,
                usedPercent: percent,
                windowMinutes: windowMinutes,
                resetsAt: end
            )
        ]
    }

    private func loadSession(allowCache: Bool) async -> CursorUsageProvider.SessionLoad {
        if allowCache, let cached = await sessionCache.load() {
            return .ready(cached)
        }
        var last: CursorUsageProvider.SessionLoad = .unavailable
        for _ in 1...2 {
            let result = await storeReader()
            last = CursorUsageProvider.session(fromSQLiteOutput: result.output, exitCode: result.exitCode)
            switch last {
            case .ready(let credentials):
                await sessionCache.store(credentials)
                return last
            case .missingAuth:
                return last
            case .unavailable:
                continue
            }
        }
        return last
    }

    private func fetchUsage(
        using credentials: CursorUsageProvider.Credentials,
        allowStoreRetry: Bool
    ) async -> UsageReading {
        var request = URLRequest(url: Self.usageURL, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = "POST"
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Data("{}".utf8)
        request.timeoutInterval = 12

        do {
            let (data, http) = try await loader(request)
            if http.statusCode == 401 || http.statusCode == 403 {
                await sessionCache.clear()
                if allowStoreRetry {
                    switch await loadSession(allowCache: false) {
                    case .ready(let refreshed):
                        return await fetchUsage(using: refreshed, allowStoreRetry: false)
                    case .missingAuth:
                        break
                    case .unavailable:
                        return makeReading(
                            status: .error("Cursor editor session store was busy or unreadable")
                        )
                    }
                }
                return makeReading(status: .needsAuth, error: "Cursor editor session expired")
            }
            guard http.statusCode == 200 else {
                return makeReading(status: .error("Grok Bot returned \(http.statusCode)"))
            }
            guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let windows = Self.windows(from: root)
            else {
                return makeReading(status: .error("Grok Bot returned no weekly allowance"))
            }
            return UsageReading(
                providerId: id,
                label: label,
                accountId: credentials.accountID,
                authMode: "subscription",
                source: "cursor_grok_bot_usage",
                windows: windows,
                status: .live,
                observedAt: Date(),
                error: nil
            )
        } catch {
            return makeReading(status: .error("Grok Bot usage request failed"))
        }
    }

    private static func percent(_ value: Any?) -> Double? {
        if value is Bool { return nil }
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            let percent = number.doubleValue
            return percent.isFinite && percent >= 0 && percent <= 1_000 ? percent : nil
        }
        return nil
    }

    private func makeReading(status: UsageReading.ReadingStatus, error: String? = nil) -> UsageReading {
        UsageReading(
            providerId: id,
            label: label,
            accountId: nil,
            authMode: "unknown",
            source: "cursor_grok_bot_usage",
            windows: [],
            status: status,
            observedAt: nil,
            error: error
        )
    }
}
