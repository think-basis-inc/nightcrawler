import Foundation

/// Reads Cursor editor usage from the session stored in its VS Code-derived
/// SQLite global-state database.
struct CursorUsageProvider: UsageProvider {
    let id = "cursor"
    let label = "Cursor"

    private static let storePath = ("~/Library/Application Support/Cursor/User/globalStorage/state.vscdb" as NSString).expandingTildeInPath

    var isAvailable: Bool {
        FileManager.default.fileExists(atPath: Self.storePath)
    }

    func read() async -> UsageReading {
        guard let credentials = await readCredentials() else {
            return makeReading(status: .needsAuth, error: "Supported Cursor editor session unavailable; sign in through Cursor")
        }

        var request = URLRequest(
            url: URL(string: "https://cursor.com/api/usage-summary")!,
            cachePolicy: .reloadIgnoringLocalCacheData
        )
        request.setValue(credentials.cookie, forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return makeReading(status: .error("Bad response"))
            }
            if http.statusCode == 401 || http.statusCode == 403 {
                return makeReading(status: .needsAuth, error: "Cursor editor session expired")
            }
            guard http.statusCode == 200 else {
                return makeReading(status: .error("Cursor returned \(http.statusCode)"))
            }

            guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let windows = Self.windows(from: root)
            else {
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

    static func windows(from root: [String: Any]) -> [UsageWindow]? {
        guard let usage = root["individualUsage"] as? [String: Any] else { return nil }
        let plan = usage["plan"] as? [String: Any] ?? [:]
        let start = ProviderHelpers.parseISO8601(root["billingCycleStart"] as? String)
        let end = ProviderHelpers.parseISO8601(root["billingCycleEnd"] as? String)
        let windowMinutes: Int? = {
            guard let start, let end, end > start else { return nil }
            return Int(end.timeIntervalSince(start) / 60)
        }()
        var windows: [UsageWindow] = []

        // Dashboard headline is totalPercentUsed, not autoPercentUsed or used/limit.
        if let totalPercent = percent(plan["totalPercentUsed"])
            ?? percent(plan["autoPercentUsed"]) {
            windows.append(percentWindow(
                id: "included",
                label: "Included usage",
                percent: totalPercent,
                windowMinutes: windowMinutes,
                resetsAt: end
            ))
        }
        if let apiPercent = percent(plan["apiPercentUsed"]) {
            windows.append(percentWindow(
                id: "api",
                label: "API usage",
                percent: apiPercent,
                windowMinutes: windowMinutes,
                resetsAt: end
            ))
        }
        if let onDemand = spendWindow(usage["onDemand"], id: "on_demand", label: "On demand", resetsAt: end) {
            windows.append(onDemand)
        }
        return windows
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

    private func readCredentials() async -> Credentials? {
        let sql = "SELECT key, value FROM ItemTable WHERE key IN ('cursorAuth/accessToken', 'cursorAuth/stripeMembershipAuthId')"
        let result = await ProcessRunner.run(command: "/usr/bin/sqlite3", arguments: ["-json", Self.storePath, sql])
        guard result.exitCode == 0,
              let json = try? JSONSerialization.jsonObject(with: result.output) as? [[String: String]]
        else { return nil }

        var values: [String: String] = [:]
        for row in json {
            if let key = row["key"], let value = row["value"] {
                values[key] = value
            }
        }

        guard let token = values["cursorAuth/accessToken"], !token.isEmpty else { return nil }
        var account = values["cursorAuth/stripeMembershipAuthId"]

        if account == nil || account!.isEmpty {
            guard let payload = ProviderHelpers.jwtPayload(token),
                  let sub = payload["sub"] as? String,
                  let idPart = sub.split(separator: "|").dropFirst().first
            else { return nil }
            account = String(idPart)
        }

        guard let account, !account.isEmpty else { return nil }
        return Credentials(
            accountID: ProviderHelpers.sha256Prefix(account),
            cookie: "WorkosCursorSessionToken=\(account)::\(token)"
        )
    }

    private static func percent(_ value: Any?) -> Double? {
        if value is Bool { return nil }
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            let percent = number.doubleValue
            return percent.isFinite && percent >= 0 && percent <= 1_000 ? percent : nil
        }
        return nil
    }

    private static func spendWindow(_ value: Any?, id: String, label: String, resetsAt: Date?) -> UsageWindow? {
        guard let bucket = value as? [String: Any],
              (bucket["enabled"] as? Bool) == true,
              let limit = (bucket["limit"] as? NSNumber)?.doubleValue, limit > 0,
              let used = (bucket["used"] as? NSNumber)?.doubleValue
        else { return nil }
        let percent = (used / limit) * 100
        return UsageWindow(
            id: id,
            label: label,
            used: Int(used),
            limit: Int(limit),
            usedPercent: percent,
            windowMinutes: nil,
            resetsAt: resetsAt
        )
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

    private struct Credentials {
        let accountID: String
        let cookie: String
    }
}
