import Foundation

/// Reads OpenCode Go plan usage from the official endpoint using the key
/// OpenCode stores on sign-in.
struct OpenCodeUsageProvider: UsageProvider {
    let id = "opencode"
    let label = "OpenCode"

    private static let authPath = ("~/.local/share/opencode/auth.json" as NSString).expandingTildeInPath
    private static let endpoint = URL(string: "https://opencode.ai/zen/go/v1/usage")!

    var isAvailable: Bool {
        loadToken() != nil
    }

    func read() async -> UsageReading {
        guard let token = loadToken() else {
            return makeReading(status: .needsAuth, error: "Run opencode auth login to enable Go usage reading")
        }

        var request = URLRequest(url: Self.endpoint, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return makeReading(status: .error("Bad response"))
            }
            if http.statusCode == 401 {
                return makeReading(status: .needsAuth, error: "OpenCode Go key expired or missing a Go plan")
            }
            if http.statusCode == 429 {
                return makeReading(status: .error("Rate limited by OpenCode"))
            }
            guard http.statusCode == 200 else {
                return makeReading(status: .error("OpenCode returned \(http.statusCode)"))
            }

            guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let usage = root["usage"] as? [String: Any]
            else {
                return makeReading(status: .error("OpenCode returned invalid usage metadata"))
            }

            let windows = makeWindows(from: usage)
            let status: UsageReading.ReadingStatus = windows.isEmpty
                ? .error("OpenCode reported no usage windows")
                : .live
            return UsageReading(
                providerId: id,
                label: label,
                accountId: nil,
                authMode: windows.isEmpty ? "unknown" : "subscription",
                source: "opencode_go_usage",
                windows: windows,
                status: status,
                observedAt: Date(),
                error: nil
            )
        } catch {
            return makeReading(status: .error("OpenCode usage request failed"))
        }
    }

    private func loadToken() -> String? {
        guard let root = ProviderHelpers.readJSONObject(at: Self.authPath),
              let entry = root["opencode-go"]
        else { return nil }

        if let token = ProviderHelpers.nonEmptyString(entry) { return token }
        guard let object = entry as? [String: Any] else { return nil }
        for key in ["key", "apiKey", "api_key", "token", "accessToken"] {
            if let token = ProviderHelpers.nonEmptyString(object[key]) { return token }
        }
        return nil
    }

    private func makeWindows(from usage: [String: Any]) -> [UsageWindow] {
        let windowSpecs: [(String, String)] = [
            ("rolling", "5h limit"),
            ("weekly", "Weekly limit"),
            ("monthly", "Monthly limit"),
        ]
        var windows: [UsageWindow] = []
        for (id, label) in windowSpecs {
            guard let entry = usage[id] as? [String: Any],
                  let percent = (entry["percent"] as? NSNumber)?.doubleValue
            else { continue }
            windows.append(UsageWindow(
                id: id,
                label: label,
                used: Int(percent * 100),
                limit: 10000,
                usedPercent: percent,
                windowMinutes: nil,
                resetsAt: ProviderHelpers.parseISO8601(entry["resetsAt"] as? String)
            ))
        }
        return windows
    }

    private func makeReading(status: UsageReading.ReadingStatus, error: String? = nil) -> UsageReading {
        UsageReading(
            providerId: id,
            label: label,
            accountId: nil,
            authMode: "unknown",
            source: "opencode_go_usage",
            windows: [],
            status: status,
            observedAt: nil,
            error: error
        )
    }
}
