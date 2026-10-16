import Foundation

/// Reads Grok subscription usage from the CLI billing endpoint using the
/// session Grok stores in ~/.grok/auth.json.
struct GrokUsageProvider: UsageProvider {
    let id = "grok"
    let label = "Grok"

    private static let trustedIssuer = "https://auth.x.ai"

    private let authPath: String
    private let loader: QuotaHTTP.Loader
    private let refresher: @Sendable () -> Void
    private let now: @Sendable () -> Date
    private let renewalGate = RenewalGate()

    init(authPath: String = ("~/.grok/auth.json" as NSString).expandingTildeInPath,
         loader: @escaping QuotaHTTP.Loader = QuotaHTTP.load,
         refresher: @escaping @Sendable () -> Void = Self.refreshWithCLI,
         now: @escaping @Sendable () -> Date = Date.init) {
        self.authPath = authPath
        self.loader = loader
        self.refresher = refresher
        self.now = now
    }

    var isAvailable: Bool {
        loadCredentials() != nil
    }

    func read() async -> UsageReading {
        guard var credentials = loadCredentials() else {
            return makeReading(status: .needsAuth, error: "Run grok login to enable usage reading")
        }
        var renewed = false
        // Time-based even for a token Grok rejected earlier: the CLI refreshes
        // once a token has expired, which it may not do for a revoked one.
        if credentials.expiresAt <= now() {
            guard let fresh = await renew(credentials, rejected: false) else {
                return makeReading(status: .needsAuth, error: "Grok login expired; run grok login")
            }
            credentials = fresh
            renewed = true
        }

        let reading = await readUsage(with: credentials)
        // A token can be revoked before its recorded expiry; renew once per
        // rejected token and retry only with the one the CLI saved instead.
        guard reading.status == .needsAuth, !renewed,
              let fresh = await renew(credentials, rejected: true)
        else { return reading }
        return await readUsage(with: fresh)
    }

    /// Lets the CLI renew the session and returns the new credentials, or nil
    /// when it saved none. Never runs two CLIs at once, since concurrent
    /// refreshes could race on a rotating refresh token.
    private func renew(_ credentials: Credentials, rejected: Bool) async -> Credentials? {
        guard credentials.canRenew,
              renewalGate.begin(at: now(), rejectedToken: rejected ? credentials.accessToken : nil)
        else { return nil }
        await Task.detached(operation: refresher).value
        let fresh = loadCredentials().flatMap {
            $0.expiresAt > now() && $0.accessToken != credentials.accessToken ? $0 : nil
        }
        renewalGate.end(at: now(), renewed: fresh != nil)
        return fresh
    }

    private func readUsage(with credentials: Credentials) async -> UsageReading {
        var request = URLRequest(
            url: URL(string: "https://cli-chat-proxy.grok.com/v1/billing?format=credits")!,
            cachePolicy: .reloadIgnoringLocalCacheData
        )
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("xai-grok-cli", forHTTPHeaderField: "X-XAI-Token-Auth")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        do {
            let (data, http) = try await loader(request)
            if http.statusCode == 401 || http.statusCode == 403 {
                return makeReading(status: .needsAuth, error: "Grok login expired")
            }
            if http.statusCode == 429 {
                return makeReading(status: .error("Rate limited by Grok"))
            }
            guard http.statusCode == 200 else {
                return makeReading(status: .error("Grok returned \(http.statusCode)"))
            }
            // The session works, however it was renewed, so a later expiry
            // starts its retries from the shortest wait.
            renewalGate.clearFailures()

            guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let config = root["config"] as? [String: Any]
            else {
                return makeReading(status: .error("Grok returned invalid usage metadata"))
            }

            let windows = Self.windows(from: config)
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
                observedAt: now(),
                error: nil
            )
        } catch {
            return makeReading(status: .error("Grok usage request failed"))
        }
    }

    private func loadCredentials() -> Credentials? {
        guard let root = ProviderHelpers.readJSONObject(at: authPath) else { return nil }

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
                ?? now().addingTimeInterval(30 * 24 * 60 * 60),
            email: ProviderHelpers.nonEmptyString(entry["email"]),
            canRenew: ProviderHelpers.nonEmptyString(entry["refresh_token"]) != nil
        )
    }

    private func isLive(_ entry: [String: Any]) -> Bool {
        guard let expires = (entry["expires_at"] as? String).flatMap(ProviderHelpers.parseISO8601) else { return true }
        return expires > now()
    }

    /// Lets the Grok CLI renew its own session. Any CLI start refreshes an
    /// expired access token from the stored refresh token, so this never reads
    /// or sends credentials itself; the caller re-reads auth.json afterwards.
    /// The generous timeout avoids killing the CLI between the server rotating
    /// the refresh token and the CLI saving it; a slow run only costs one read.
    static func refreshWithCLI() {
        guard let executable = RestrictedProcess.resolveOnPath("grok") else { return }
        _ = CopilotBillingClient.run([executable, "models"], timeout: 30, maxBytes: 1_048_576)
    }

    static func windows(from config: [String: Any]) -> [UsageWindow] {
        var result: [UsageWindow] = []
        let periodEnd = date(config["currentPeriod"] as? [String: Any])?["end"]
            ?? ProviderHelpers.parseISO8601(config["billingPeriodEnd"] as? String)

        if let percent = percent(config["creditUsagePercent"]) {
            result.append(UsageWindow(
                id: "credits",
                label: totalLabel(config),
                used: Int(percent * 100),
                limit: 10000,
                usedPercent: percent,
                windowMinutes: windowMinutes(config["currentPeriod"] as? [String: Any]),
                resetsAt: periodEnd
            ))
        }

        if let products = config["productUsage"] as? [[String: Any]] {
            for product in products {
                guard let percent = percent(product["usagePercent"]) else { continue }
                let name = humanize((product["product"] as? String) ?? "Usage")
                result.append(UsageWindow(
                    id: (product["product"] as? String) ?? name,
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

    private static func totalLabel(_ config: [String: Any]) -> String {
        let period = config["currentPeriod"] as? [String: Any]
        if (period?["type"] as? String) == "USAGE_PERIOD_TYPE_WEEKLY" {
            return "Weekly SuperGrok Heavy Limit"
        }
        return "SuperGrok Heavy Limit"
    }

    private static func humanize(_ name: String) -> String {
        var result = ""
        for character in name {
            if character.isUppercase, !result.isEmpty { result.append(" ") }
            result.append(character)
        }
        return result
    }

    private static func date(_ period: [String: Any]?) -> [String: Date]? {
        guard let period else { return nil }
        return [
            "start": ProviderHelpers.parseISO8601(period["start"] as? String),
            "end": ProviderHelpers.parseISO8601(period["end"] as? String)
        ].compactMapValues { $0 }
    }

    private static func windowMinutes(_ period: [String: Any]?) -> Int? {
        guard let dates = date(period), let start = dates["start"], let end = dates["end"], end > start else { return nil }
        return Int(end.timeIntervalSince(start) / 60)
    }

    private static func percent(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber else { return nil }
        let percent = number.doubleValue
        guard percent.isFinite, (0...100).contains(percent) else { return nil }
        return percent
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
        let canRenew: Bool
    }

    /// One CLI renewal at a time. Failures back off from two minutes up to an
    /// hour so a wake without network retries soon but a broken CLI does not
    /// relaunch every poll; a token Grok rejects is renewed only once.
    private final class RenewalGate: @unchecked Sendable {
        private let lock = NSLock()
        private var running = false
        private var failures = 0
        private var nextAttempt = Date.distantPast
        private var lastRejectedToken: String?

        func begin(at date: Date, rejectedToken: String?) -> Bool {
            lock.withLock {
                guard !running, date >= nextAttempt else { return false }
                if let rejectedToken {
                    guard rejectedToken != lastRejectedToken else { return false }
                    lastRejectedToken = rejectedToken
                }
                running = true
                return true
            }
        }

        func clearFailures() {
            lock.withLock {
                failures = 0
                nextAttempt = .distantPast
            }
        }

        func end(at date: Date, renewed: Bool) {
            lock.withLock {
                running = false
                failures = renewed ? 0 : failures + 1
                nextAttempt = renewed ? date : date.addingTimeInterval(min(120 * pow(2, Double(failures - 1)), 3600))
            }
        }
    }
}
