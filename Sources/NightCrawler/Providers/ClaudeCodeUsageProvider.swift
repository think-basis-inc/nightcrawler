import Foundation

/// Reads Claude Code usage from Anthropic's OAuth endpoint using the token
/// Claude Code already stores in the macOS Keychain.
struct ClaudeCodeUsageProvider: UsageProvider {
    let id = "claude"
    let label = "Claude Code"

    private let credentials: ClaudeCredentialStore

    init(credentials: ClaudeCredentialStore = .shared) {
        self.credentials = credentials
    }

    var isAvailable: Bool { true }

    func read() async -> UsageReading {
        guard let token = await credentials.read() else {
            return makeReading(status: .needsAuth, error: "Sign in to Claude Code to refresh its subscription login")
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
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return makeReading(status: .error("Bad response"))
            }
            if http.statusCode == 401 || http.statusCode == 403 {
                return makeReading(status: .needsAuth, error: "Claude subscription login expired")
            }
            if http.statusCode == 429 {
                return makeReading(status: .error("Rate limited by Claude"))
            }
            guard http.statusCode == 200 else {
                return makeReading(status: .error("Claude returned \(http.statusCode)"))
            }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let payload = try decoder.decode(UsageResponse.self, from: data)
            let windows = payload.windows()
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
            return makeReading(status: .error("Claude usage request failed"))
        }
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
