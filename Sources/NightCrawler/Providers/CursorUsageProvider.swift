import Foundation

/// Reads Cursor editor usage from the session stored in its VS Code-derived
/// SQLite global-state database.
struct CursorUsageProvider: UsageProvider {
    let id = "cursor"
    let label = "Cursor"

    typealias StoreReader = @Sendable () async -> ProcessRunner.RunResult
    typealias Loader = QuotaHTTP.Loader

    static let defaultStorePath = ("~/Library/Application Support/Cursor/User/globalStorage/state.vscdb" as NSString).expandingTildeInPath
    static let usageSummaryURL = URL(string: "https://cursor.com/api/usage-summary")!
    static let liveRefreshInterval: TimeInterval = 15

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

    static let sessionSQL = "SELECT key, value FROM ItemTable WHERE key IN ('cursorAuth/accessToken', 'cursorAuth/stripeMembershipAuthId')"

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

    static func windows(from root: [String: Any], sand _: [String: Any]? = nil) -> [UsageWindow]? {
        let start = ProviderHelpers.parseISO8601(root["billingCycleStart"] as? String)
        let end = ProviderHelpers.parseISO8601(root["billingCycleEnd"] as? String)
        let windowMinutes: Int? = {
            guard let start, let end, end > start else { return nil }
            return Int(end.timeIntervalSince(start) / 60)
        }()
        let usage = (root["individualUsage"] as? [String: Any])
            ?? (root["teamUsage"] as? [String: Any])
        let windows = planWindows(from: usage, windowMinutes: windowMinutes, resetsAt: end)
        return windows.isEmpty ? nil : windows
    }

    private static func percentWindow(
        id: String,
        label: String,
        percent: Double,
        windowMinutes: Int?,
        resetsAt: Date?
    ) -> UsageWindow {
        UsageWindow(
            id: id,
            label: label,
            used: Int(percent * 100),
            limit: 10_000,
            usedPercent: percent,
            windowMinutes: windowMinutes,
            resetsAt: resetsAt
        )
    }

    private func loadSession(allowCache: Bool) async -> SessionLoad {
        if allowCache, let cached = await sessionCache.load() {
            return .ready(cached)
        }
        var last: SessionLoad = .unavailable
        for _ in 1...2 {
            let result = await storeReader()
            last = Self.session(fromSQLiteOutput: result.output, exitCode: result.exitCode)
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

    private func fetchUsage(using credentials: Credentials, allowStoreRetry: Bool) async -> UsageReading {
        var request = URLRequest(
            url: Self.usageSummaryURL,
            cachePolicy: .reloadIgnoringLocalCacheData
        )
        request.setValue(credentials.cookie, forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
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
                return makeReading(status: .error("Cursor returned \(http.statusCode)"))
            }

            guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return makeReading(status: .error("Cursor returned invalid usage metadata"))
            }
            guard let windows = Self.windows(from: root) else {
                return makeReading(status: .error("Cursor returned invalid usage metadata"))
            }

            let status: UsageReading.ReadingStatus = windows.isEmpty
                ? .error("Cursor returned no finite usage allowance")
                : .live
            return UsageReading(
                providerId: id,
                label: label,
                accountId: credentials.accountID,
                authMode: "subscription",
                source: "cursor_editor_usage",
                windows: windows,
                status: status,
                observedAt: Date(),
                error: nil
            )
        } catch {
            return makeReading(status: .error("Cursor usage request failed"))
        }
    }

    private static func planWindows(
        from usage: [String: Any]?,
        windowMinutes: Int?,
        resetsAt: Date?
    ) -> [UsageWindow] {
        guard let usage else { return [] }
        let plan = usage["plan"] as? [String: Any] ?? [:]
        var windows: [UsageWindow] = []

        // Dashboard headline is included total usage. Auto/used-limit can read
        // 100% while included still has room; never treat spend as the percent.
        if let includedPercent = usedPercent(
            used: plan["totalPercentUsed"],
            remaining: nil
        ) ?? usedPercent(
            used: plan["autoPercentUsed"],
            remaining: plan["autoPercentRemaining"] ?? plan["autoPercentLeft"]
        ) {
            windows.append(percentWindow(
                id: "included",
                label: "Included models",
                percent: includedPercent,
                windowMinutes: windowMinutes,
                resetsAt: resetsAt
            ))
        }
        if let apiPercent = usedPercent(
            used: plan["apiPercentUsed"],
            remaining: plan["apiPercentRemaining"] ?? plan["apiPercentLeft"]
        ) {
            windows.append(percentWindow(
                id: "api",
                label: "Other Models",
                percent: apiPercent,
                windowMinutes: windowMinutes,
                resetsAt: resetsAt
            ))
        }
        return windows
    }

    static func session(fromSQLiteOutput data: Data, exitCode: Int32) -> SessionLoad {
        guard exitCode == 0,
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: String]]
        else { return .unavailable }

        var values: [String: String] = [:]
        for row in json {
            if let key = row["key"], let value = row["value"] {
                values[key] = value
            }
        }

        guard let token = values["cursorAuth/accessToken"], !token.isEmpty else { return .missingAuth }
        var account = values["cursorAuth/stripeMembershipAuthId"]

        if account == nil || account!.isEmpty {
            guard let payload = ProviderHelpers.jwtPayload(token),
                  let sub = payload["sub"] as? String,
                  let idPart = sub.split(separator: "|").dropFirst().first
            else { return .missingAuth }
            account = String(idPart)
        }

        guard let account, !account.isEmpty else { return .missingAuth }
        return .ready(
            Credentials(
                accountID: ProviderHelpers.sha256Prefix(account),
                cookie: "WorkosCursorSessionToken=\(account)::\(token)",
                accessToken: token
            )
        )
    }

    enum SessionLoad: Equatable, Sendable {
        case ready(Credentials)
        case missingAuth
        case unavailable
    }

    struct Credentials: Equatable, Sendable {
        let accountID: String
        let cookie: String
        let accessToken: String
    }

    private static func usedPercent(used: Any?, remaining: Any?) -> Double? {
        if let used = percent(used) { return used }
        guard let remaining = percent(remaining) else { return nil }
        return max(0, 100 - remaining)
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
            source: "cursor_editor_usage",
            windows: [],
            status: status,
            observedAt: nil,
            error: error
        )
    }
}

actor CursorSessionCache: Sendable {
    static let shared = CursorSessionCache()

    private var credentials: CursorUsageProvider.Credentials?

    func load() -> CursorUsageProvider.Credentials? { credentials }

    func store(_ credentials: CursorUsageProvider.Credentials) {
        self.credentials = credentials
    }

    func clear() {
        credentials = nil
    }
}
