import Foundation
import Security

/// Reads GitHub Copilot premium request usage from GitHub's billing API.
/// Expects a Personal Access Token with `Plan` read-only permission stored
/// in the macOS Keychain under the service name `nightcrawler.github.copilot`.
struct GitHubCopilotUsageProvider: UsageProvider {
    let id = "copilot"
    let label = "GitHub Copilot"

    private static let keychainService = "nightcrawler.github.copilot"
    private static let keychainAccount = "token"

    var isAvailable: Bool {
        // Disabled by default to avoid keychain prompts. Enable in Settings once
        // you have added the GitHub PAT and are ready to grant access.
        false
    }

    func read() async -> UsageReading {
        guard let token = getToken() else {
            return makeReading(status: .needsAuth, error: "Add a GitHub PAT with Plan read permission to the Keychain")
        }

        var request = URLRequest(
            url: URL(string: "https://api.github.com/users/copilot/usage")!,
            cachePolicy: .reloadIgnoringLocalCacheData
        )
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return makeReading(status: .error("Bad response"))
            }
            if http.statusCode == 401 || http.statusCode == 403 {
                return makeReading(status: .needsAuth, error: "GitHub token lacks Copilot billing permission")
            }
            guard http.statusCode == 200 else {
                return makeReading(status: .error("GitHub returned \(http.statusCode)"))
            }
            let payload = try JSONDecoder().decode(CopilotUsage.self, from: data)
            let used = payload.total_requests
            let limit = payload.plan_limit
            let percent = limit > 0 ? (Double(used) / Double(limit)) * 100 : 0
            let window = UsageWindow(
                id: "premium_interactions",
                label: "Premium requests",
                used: used,
                limit: limit,
                usedPercent: percent,
                windowMinutes: nil,
                resetsAt: parseResetDate(payload.reset_date)
            )
            return UsageReading(
                providerId: id,
                label: label,
                accountId: nil,
                authMode: "subscription",
                source: "github_copilot_billing",
                windows: limit > 0 ? [window] : [],
                status: limit > 0 ? .live : .error("No finite Copilot subscription allowance reported"),
                observedAt: Date(),
                error: nil
            )
        } catch {
            return makeReading(status: .error("Request failed"))
        }
    }

    private func getToken() -> String? {
        Keychain.readPassword(service: Self.keychainService, account: Self.keychainAccount)
    }

    private func parseResetDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.date(from: value)
    }

    private func makeReading(status: UsageReading.ReadingStatus, error: String? = nil) -> UsageReading {
        UsageReading(
            providerId: id,
            label: label,
            accountId: nil,
            authMode: "unknown",
            source: "github_copilot_billing",
            windows: [],
            status: status,
            observedAt: nil,
            error: error
        )
    }
}

private struct CopilotUsage: Decodable {
    let total_requests: Int
    let plan_limit: Int
    let reset_date: String?
}
