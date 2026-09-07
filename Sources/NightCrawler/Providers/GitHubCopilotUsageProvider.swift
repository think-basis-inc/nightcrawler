import Foundation
import Security

/// Reads GitHub Copilot premium request usage from GitHub's billing API.
/// Expects a Personal Access Token with `Plan` read-only permission stored
/// in the macOS Keychain under the service name `nightcrawler.github.copilot`.
actor GitHubCopilotUsageProvider: UsageProvider {
    let id = "copilot"
    let label = "GitHub Copilot"

    private static let keychainService = "nightcrawler.github.copilot"
    private static let keychainAccount = "token"

    func read() async throws -> UsageReading? {
        guard let token = getToken() else {
            return UsageReading(
                providerId: id,
                label: label,
                percentUsed: 0,
                used: 0,
                limit: 0,
                windowName: "Premium requests",
                resetsAt: nil,
                status: .needsAuth
            )
        }

        let request = URLRequest(
            url: URL(string: "https://api.github.com/users/copilot/usage")!,
            cachePolicy: .reloadIgnoringLocalCacheData
        )
        var mutable = request
        mutable.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        mutable.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: mutable)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if http.statusCode == 401 {
            return UsageReading(
                providerId: id,
                label: label,
                percentUsed: 0,
                used: 0,
                limit: 0,
                windowName: "Premium requests",
                resetsAt: nil,
                status: .needsAuth
            )
        }
        guard http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let payload = try JSONDecoder().decode(CopilotUsage.self, from: data)
        let used = payload.total_requests
        let limit = payload.plan_limit
        let fraction = limit > 0 ? Double(used) / Double(limit) : 0

        return UsageReading(
            providerId: id,
            label: label,
            percentUsed: fraction * 100,
            used: used,
            limit: limit,
            windowName: "Premium requests",
            resetsAt: payload.reset_date.flatMap { parseResetDate($0) },
            status: fraction >= 0.9 ? .critical : fraction >= 0.7 ? .warning : .ok
        )
    }

    private func getToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func parseResetDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.date(from: value)
    }
}

private struct CopilotUsage: Decodable {
    let total_requests: Int
    let plan_limit: Int
    let reset_date: String?
}
