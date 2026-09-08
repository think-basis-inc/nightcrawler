import Foundation

/// Reads Codex CLI usage from the ChatGPT backend using the session Codex
/// stores in ~/.codex/auth.json.
struct CodexCLIUsageProvider: UsageProvider {
    let id = "codex"
    let label = "Codex CLI"

    private static let authPath = ("~/.codex/auth.json" as NSString).expandingTildeInPath
    private let sessionUsage: CodexSessionUsageReader

    init(sessionUsage: CodexSessionUsageReader = CodexSessionUsageReader()) {
        self.sessionUsage = sessionUsage
    }

    var isAvailable: Bool {
        loadCredentials() != nil
    }

    func read() async -> UsageReading {
        let sessionReading = sessionUsage.read()
        if let sessionReading,
           let observedAt = sessionReading.observedAt,
           Date().timeIntervalSince(observedAt) < 15 * 60 {
            return sessionReading
        }
        guard let credentials = loadCredentials() else {
            return sessionReading
                ?? makeReading(status: .needsAuth, error: "Sign in to Codex CLI to read usage")
        }

        var request = URLRequest(
            url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!,
            cachePolicy: .reloadIgnoringLocalCacheData
        )
        request.httpMethod = "GET"
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(credentials.accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return makeReading(status: .error("Bad response"))
            }
            if http.statusCode == 401 || http.statusCode == 403 {
                return sessionReading
                    ?? makeReading(status: .needsAuth, error: "Codex CLI session expired")
            }
            guard http.statusCode == 200 else {
                return sessionReading
                    ?? makeReading(status: .error("ChatGPT returned \(http.statusCode)"))
            }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let payload = try decoder.decode(UsageResponse.self, from: data)
            let windows = payload.windows()
            let status: UsageReading.ReadingStatus = windows.isEmpty
                ? .error("Codex reported no usage windows")
                : .live
            return UsageReading(
                providerId: id,
                label: label,
                accountId: credentials.accountID,
                authMode: windows.isEmpty ? "unknown" : "subscription",
                source: "codex_cli_usage",
                windows: windows,
                status: status,
                observedAt: Date(),
                error: nil
            )
        } catch {
            return sessionReading
                ?? makeReading(status: .error("Codex usage request failed"))
        }
    }

    private func loadCredentials() -> Credentials? {
        guard let root = ProviderHelpers.readJSONObject(at: Self.authPath),
              let tokens = root["tokens"] as? [String: Any],
              let accessToken = ProviderHelpers.nonEmptyString(tokens["access_token"]),
              let accountID = ProviderHelpers.nonEmptyString(tokens["account_id"])
        else { return nil }

        if let payload = ProviderHelpers.jwtPayload(accessToken),
           let exp = payload["exp"] as? Double,
           exp <= Date().timeIntervalSince1970 {
            return nil
        }

        return Credentials(accessToken: accessToken, accountID: accountID)
    }

    private func makeReading(status: UsageReading.ReadingStatus, error: String? = nil) -> UsageReading {
        UsageReading(
            providerId: id,
            label: label,
            accountId: nil,
            authMode: "unknown",
            source: "codex_cli_usage",
            windows: [],
            status: status,
            observedAt: nil,
            error: error
        )
    }

    private struct Credentials {
        let accessToken: String
        let accountID: String
    }

    private struct UsageResponse: Decodable {
        struct RateLimit: Decodable {
            let primaryWindow: Window?
            let secondaryWindow: Window?
        }

        struct Window: Decodable {
            let limitWindowSeconds: Double
            let usedPercent: Double?
            let resetAt: Double?
            let resetAfterSeconds: Double?
        }

        let rateLimit: RateLimit?

        func windows(now: Date = Date()) -> [UsageWindow] {
            var result: [UsageWindow] = []
            let pairs: [(String, String, Window?)] = [
                ("primary", CodexUsageLabels.label(windowSeconds: rateLimit?.primaryWindow?.limitWindowSeconds), rateLimit?.primaryWindow),
                ("secondary", CodexUsageLabels.label(windowSeconds: rateLimit?.secondaryWindow?.limitWindowSeconds), rateLimit?.secondaryWindow),
            ]
            for (id, label, window) in pairs {
                guard let window, let percent = window.usedPercent else { continue }
                let resetsAt = window.resetAt.map { Date(timeIntervalSince1970: $0) }
                    ?? window.resetAfterSeconds.map { now.addingTimeInterval($0) }
                result.append(UsageWindow(
                    id: id,
                    label: label,
                    used: Int(percent * 100),
                    limit: 10000,
                    usedPercent: percent,
                    windowMinutes: Int(window.limitWindowSeconds / 60),
                    resetsAt: resetsAt
                ))
            }
            return result
        }
    }
}

enum CodexUsageLabels {
    static func label(windowSeconds seconds: Double?) -> String {
        guard let seconds, seconds > 0 else { return "Usage limit" }
        if abs(seconds - 18_000) < 60 { return "Current session" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(Int(minutes))m limit" }
        if minutes < 60 * 24 { return "\(Int(minutes / 60))h limit" }
        let days = Int((minutes / (60 * 24)).rounded())
        switch days {
        case 7: return "Weekly limit"
        case 30: return "Monthly limit"
        default: return "\(days)d limit"
        }
    }
}
