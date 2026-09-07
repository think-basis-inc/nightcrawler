import Foundation

/// Reads Z.ai / GLM Coding Plan usage from whichever local tool already holds
/// the key: Claude Code settings, ZCode config/credentials, or OpenCode auth.
struct ZCodeUsageProvider: UsageProvider {
    let id = "zcode"
    let label = "ZCode / GLM"

    private static let claudeSettingsPath = ("~/.claude/settings.json" as NSString).expandingTildeInPath
    private static let zcodeConfigPath = ("~/.zcode/v2/config.json" as NSString).expandingTildeInPath
    private static let zcodeCredentialsPath = ("~/.zcode/v2/credentials.json" as NSString).expandingTildeInPath
    private static let openCodeAuthPath = ("~/.local/share/opencode/auth.json" as NSString).expandingTildeInPath
    private static let encryptedMarker = "enc:v1:"

    var isAvailable: Bool {
        loadCredentials() != nil
    }

    func read() async -> UsageReading {
        guard let credentials = loadCredentials() else {
            return makeReading(status: .needsAuth, error: "Configure a Z.ai GLM Coding Plan key in Claude Code, ZCode, or OpenCode")
        }

        var request = URLRequest(
            url: credentials.baseURL.appendingPathComponent("api/monitor/usage/quota/limit"),
            cachePolicy: .reloadIgnoringLocalCacheData
        )
        request.setValue(credentials.token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return makeReading(status: .error("Bad response"))
            }
            if http.statusCode == 401 || http.statusCode == 403 {
                return makeReading(status: .needsAuth, error: "GLM key rejected; check the configured key")
            }
            if http.statusCode == 429 {
                return makeReading(status: .error("Rate limited by Z.ai"))
            }
            guard http.statusCode == 200 else {
                return makeReading(status: .error("Z.ai returned \(http.statusCode)"))
            }

            let payload = try JSONDecoder().decode(UsageResponse.self, from: data)
            guard payload.succeeded else {
                if let error = payload.failure {
                    return makeReading(status: error)
                }
                return makeReading(status: .error("Z.ai returned an error"))
            }

            let windows = payload.windows.sorted {
                rank($0.id) < rank($1.id)
            }
            let status: UsageReading.ReadingStatus = windows.isEmpty
                ? .error("Z.ai reported no usage windows")
                : .live
            return UsageReading(
                providerId: id,
                label: label,
                accountId: nil,
                authMode: windows.isEmpty ? "unknown" : "subscription",
                source: "zcode_glm_usage",
                windows: windows,
                status: status,
                observedAt: Date(),
                error: nil
            )
        } catch {
            return makeReading(status: .error("Z.ai usage request failed"))
        }
    }

    private func loadCredentials() -> Credentials? {
        if let credentials = claudeCodeCredentials() { return credentials }
        if let credentials = zcodePlanKey() { return credentials }
        if let credentials = zcodeOAuth() { return credentials }
        if let credentials = openCodeCredentials() { return credentials }
        return nil
    }

    private func claudeCodeCredentials() -> Credentials? {
        guard let root = ProviderHelpers.readJSONObject(at: Self.claudeSettingsPath),
              let env = root["env"] as? [String: Any],
              let token = ProviderHelpers.nonEmptyString(env["ANTHROPIC_AUTH_TOKEN"]) ?? ProviderHelpers.nonEmptyString(env["ANTHROPIC_API_KEY"]),
              let baseURLString = ProviderHelpers.nonEmptyString(env["ANTHROPIC_BASE_URL"]),
              let baseURL = URL(string: baseURLString),
              isZaiHost(baseURL.host ?? "")
        else { return nil }
        return Credentials(token: token, baseURL: consoleBase(from: baseURL.host ?? ""))
    }

    private func zcodePlanKey() -> Credentials? {
        guard let root = ProviderHelpers.readJSONObject(at: Self.zcodeConfigPath),
              let providers = root["provider"] as? [String: Any]
        else { return nil }

        for (id, value) in providers.sorted(by: { $0.key < $1.key }) {
            guard id.contains("coding-plan"),
                  let provider = value as? [String: Any],
                  let options = provider["options"] as? [String: Any],
                  let token = ProviderHelpers.nonEmptyString(options["apiKey"])
            else { continue }
            if let enabled = provider["enabled"] as? Bool, !enabled { continue }

            let baseURLString = ProviderHelpers.nonEmptyString(options["baseURL"])
            let baseURL = baseURLString.flatMap(URL.init).flatMap { isZaiHost($0.host ?? "") ? consoleBase(from: $0.host ?? "") : nil }
            return Credentials(token: token, baseURL: baseURL ?? URL(string: "https://api.z.ai")!)
        }
        return nil
    }

    private func zcodeOAuth() -> Credentials? {
        guard let root = ProviderHelpers.readJSONObject(at: Self.zcodeCredentialsPath),
              let token = ProviderHelpers.nonEmptyString(root["oauth:zai:access_token"]),
              !token.hasPrefix(Self.encryptedMarker)
        else { return nil }
        return Credentials(token: token, baseURL: URL(string: "https://api.z.ai")!)
    }

    private func openCodeCredentials() -> Credentials? {
        guard let root = ProviderHelpers.readJSONObject(at: Self.openCodeAuthPath) else { return nil }
        for id in ["zai-coding-plan", "zai", "z-ai", "z.ai", "zhipu", "zhipuai"] {
            guard let entry = root[id] else { continue }
            if let token = ProviderHelpers.nonEmptyString(entry) {
                return Credentials(token: token, baseURL: console(forProviderID: id))
            }
            if let object = entry as? [String: Any] {
                for key in ["apiKey", "api_key", "token", "key", "accessToken", "auth_token"] {
                    if let token = ProviderHelpers.nonEmptyString(object[key]) {
                        return Credentials(token: token, baseURL: console(forProviderID: id))
                    }
                }
            }
        }
        return nil
    }

    private func console(forProviderID id: String) -> URL {
        id.hasPrefix("zhipu")
            ? URL(string: "https://open.bigmodel.cn")!
            : URL(string: "https://api.z.ai")!
    }

    private func consoleBase(from host: String) -> URL {
        host.hasSuffix("bigmodel.cn")
            ? URL(string: "https://open.bigmodel.cn")!
            : URL(string: "https://api.z.ai")!
    }

    private func isZaiHost(_ host: String) -> Bool {
        host == "api.z.ai" || host.hasSuffix(".z.ai")
            || host == "open.bigmodel.cn" || host.hasSuffix(".bigmodel.cn")
    }

    private func rank(_ id: String) -> Int {
        switch id {
        case "session": return 0
        case "weekly": return 1
        case "mcp": return 2
        default: return 3
        }
    }

    private func makeReading(status: UsageReading.ReadingStatus, error: String? = nil) -> UsageReading {
        UsageReading(
            providerId: id,
            label: label,
            accountId: nil,
            authMode: "unknown",
            source: "zcode_glm_usage",
            windows: [],
            status: status,
            observedAt: nil,
            error: error
        )
    }

    private struct Credentials {
        let token: String
        let baseURL: URL
    }

    private struct UsageResponse: Decodable {
        struct Limit: Decodable {
            let type: String?
            let unit: Int?
            let number: Int?
            let percentage: Double?
            let currentValue: Double?
            let usage: Double?
            let total: Double?
            let nextResetTime: Double?
        }
        struct Data: Decodable {
            let level: String?
            let limits: [Limit]?
        }

        let code: Int?
        let success: Bool?
        let msg: String?
        let data: Data?

        var succeeded: Bool {
            (success ?? false) || code == nil || code == 200
        }

        var failure: UsageReading.ReadingStatus? {
            guard !succeeded else { return nil }
            switch code {
            case 401, 403: return .needsAuth
            case 429: return .error("Rate limited by Z.ai")
            case .some(let code): return .error("Z.ai returned \(code)")
            case nil: return .error("Z.ai returned an error")
            }
        }

        var windows: [UsageWindow] {
            (data?.limits ?? []).compactMap { limit in
                guard let percentage = limit.percentage else { return nil }
                return UsageWindow(
                    id: windowID(for: limit),
                    label: windowLabel(for: limit),
                    used: Int(percentage * 100),
                    limit: 10000,
                    usedPercent: percentage,
                    windowMinutes: nil,
                    resetsAt: limit.nextResetTime.map { Date(timeIntervalSince1970: $0 / 1000) }
                )
            }
        }

        private func windowID(for limit: Limit) -> String {
            switch limit.type {
            case "TIME_LIMIT": return "mcp"
            default:
                switch (limit.unit, limit.number) {
                case (3?, 5?): return "session"
                case (6?, 1?): return "weekly"
                case (.some(let unit), .some(let number)): return "window-\(unit)x\(number)"
                default: return limit.type?.lowercased() ?? "unknown"
                }
            }
        }

        private func windowLabel(for limit: Limit) -> String {
            switch windowID(for: limit) {
            case "session": return "Current session"
            case "weekly": return "Weekly"
            case "mcp": return "MCP (1 month)"
            default: return "Usage"
            }
        }
    }

    private struct UsageError: Error {
        let status: UsageReading.ReadingStatus
        let message: String?
    }
}
