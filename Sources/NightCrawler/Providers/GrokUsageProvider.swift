import Foundation

/// Reads Grok subscription usage from the CLI billing endpoint using the
/// session Grok stores in ~/.grok/auth.json.
struct GrokUsageProvider: UsageProvider {
    let id = "grok"
    let label = "Grok"

    private static let authPath = ("~/.grok/auth.json" as NSString).expandingTildeInPath
    private static let trustedIssuer = "https://auth.x.ai"

    var isAvailable: Bool {
        loadCredentials() != nil
    }

    func read() async -> UsageReading {
        guard let credentials = loadCredentials() else {
            return makeReading(status: .needsAuth, error: "Run grok login to enable usage reading")
        }
        guard !credentials.isExpired else {
            return makeReading(status: .needsAuth, error: "Grok login expired; run grok login")
        }

        var request = URLRequest(
            url: URL(string: "https://cli-chat-proxy.grok.com/v1/billing?format=credits")!,
            cachePolicy: .reloadIgnoringLocalCacheData
        )
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("xai-grok-cli", forHTTPHeaderField: "X-XAI-Token-Auth")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return makeReading(status: .error("Bad response"))
            }
            if http.statusCode == 401 || http.statusCode == 403 {
                return makeReading(status: .needsAuth, error: "Grok login expired")
            }
            if http.statusCode == 429 {
                return makeReading(status: .error("Rate limited by Grok"))
            }
            guard http.statusCode == 200 else {
                return makeReading(status: .error("Grok returned \(http.statusCode)"))
            }

            guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let config = root["config"] as? [String: Any]
            else {
                return makeReading(status: .error("Grok returned invalid usage metadata"))
            }

            let windows = windows(from: config)
            let status: UsageReading.ReadingStatus = windows.isEmpty
                ? .error("Grok has nothing metered on this account")
                : .live
            return UsageReading(
                providerId: id,
                label: label,
                accountId: credentials.email,
                authMode: windows.isEmpty ? "unknown" : "subscription",
                source: "grok_cli_billing",
                windows: windows,
                status: status,
                observedAt: Date(),
                error: nil
            )
        } catch {
            return makeReading(status: .error("Grok usage request failed"))
        }
    }

    private func loadCredentials() -> Credentials? {
        guard let root = ProviderHelpers.readJSONObject(at: Self.authPath) else { return nil }

        var chosen: [String: Any]?
        for (key, value) in root {
            guard let entry = value as? [String: Any] else { continue }
            if key.hasPrefix(Self.trustedIssuer) || (entry["oidc_issuer"] as? String) == Self.trustedIssuer {
                chosen = entry
                if isLive(entry) { break }
            }
        }
        guard let entry = chosen,
              let token = ProviderHelpers.nonEmptyString(entry["key"])
        else { return nil }

        return Credentials(
            accessToken: token,
            expiresAt: (entry["expires_at"] as? String).flatMap(ProviderHelpers.parseISO8601)
                ?? Date().addingTimeInterval(30 * 24 * 60 * 60),
            email: ProviderHelpers.nonEmptyString(entry["email"])
        )
    }

    private func isLive(_ entry: [String: Any]) -> Bool {
        guard let expires = (entry["expires_at"] as? String).flatMap(ProviderHelpers.parseISO8601) else { return true }
        return expires > Date()
    }

    private func windows(from config: [String: Any]) -> [UsageWindow] {
        var result: [UsageWindow] = []
        let periodEnd = date(config["currentPeriod"] as? [String: Any])?["end"]
            ?? ProviderHelpers.parseISO8601(config["billingPeriodEnd"] as? String)

        if let percent = percent(config["creditUsagePercent"]) {
            result.append(UsageWindow(
                id: "credits",
                label: productLabel(config) ?? "Grok Build",
                used: Int(percent * 100),
                limit: 10000,
                usedPercent: percent,
                windowMinutes: windowMinutes(config["currentPeriod"] as? [String: Any]),
                resetsAt: periodEnd
            ))
        } else if let products = config["productUsage"] as? [[String: Any]] {
            for product in products {
                guard let percent = percent(product["usagePercent"]) else { continue }
                let name = humanize((product["product"] as? String) ?? "Usage")
                result.append(UsageWindow(
                    id: result.isEmpty ? "credits" : ((product["product"] as? String) ?? name),
                    label: name,
                    used: Int(percent * 100),
                    limit: 10000,
                    usedPercent: percent,
                    windowMinutes: windowMinutes(config["currentPeriod"] as? [String: Any]),
                    resetsAt: periodEnd
                ))
            }
        }

        return result
    }

    private func productLabel(_ config: [String: Any]) -> String? {
        guard let products = config["productUsage"] as? [[String: Any]],
              let name = products.first?["product"] as? String
        else { return nil }
        return humanize(name)
    }

    private func humanize(_ name: String) -> String {
        var result = ""
        for character in name {
            if character.isUppercase, !result.isEmpty { result.append(" ") }
            result.append(character)
        }
        return result
    }

    private func date(_ period: [String: Any]?) -> [String: Date]? {
        guard let period else { return nil }
        return [
            "start": ProviderHelpers.parseISO8601(period["start"] as? String),
            "end": ProviderHelpers.parseISO8601(period["end"] as? String)
        ].compactMapValues { $0 }
    }

    private func windowMinutes(_ period: [String: Any]?) -> Int? {
        guard let dates = date(period), let start = dates["start"], let end = dates["end"], end > start else { return nil }
        return Int(end.timeIntervalSince(start) / 60)
    }

    private func percent(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }

    private func makeReading(status: UsageReading.ReadingStatus, error: String? = nil) -> UsageReading {
        UsageReading(
            providerId: id,
            label: label,
            accountId: nil,
            authMode: "unknown",
            source: "grok_cli_billing",
            windows: [],
            status: status,
            observedAt: nil,
            error: error
        )
    }

    private struct Credentials {
        let accessToken: String
        let expiresAt: Date
        let email: String?

        var isExpired: Bool { expiresAt <= Date() }
    }
}
