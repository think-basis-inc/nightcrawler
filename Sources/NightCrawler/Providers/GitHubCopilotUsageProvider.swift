import Foundation

/// Reads GitHub Copilot quota through the Copilot CLI's metadata-only
/// stdio JSON-RPC, then `GET /copilot_internal/user`, then premium-request billing.
struct GitHubCopilotUsageProvider: UsageProvider {
    let id = "copilot"
    let label = "GitHub Copilot"

    var isAvailable: Bool {
        CopilotRPCClient.defaultCommand() != nil
    }

    func read() async -> UsageReading {
        guard let command = CopilotRPCClient.defaultCommand() else {
            return makeReading(
                status: .needsAuth,
                error: "Install and sign in to GitHub Copilot CLI to read usage"
            )
        }
        var result = await CopilotRPCClient(command: command, timeout: 19).query()
        if result.windows.isEmpty, result.status != .needsAuth {
            let client = CopilotBillingClient(planLimit: CopilotPlanSettings.current())
            result = Self.reconcile(cli: result, billing: await client.queryInternalUser())
            if result.windows.isEmpty, result.status != .needsAuth {
                result = Self.reconcile(cli: result, billing: await client.query())
            }
        }
        return map(result)
    }

    static func reconcile(
        cli: CopilotQuotaParser.Result,
        billing: CopilotQuotaParser.Result
    ) -> CopilotQuotaParser.Result {
        if !billing.windows.isEmpty {
            var measured = billing
            measured.accountId = cli.accountId
            return measured
        }
        if billing.status == .needsAuth, cli.status != .needsAuth {
            var authenticated = cli
            authenticated.status = .unknown
            authenticated.error = billing.error
            return authenticated
        }
        return cli
    }

    static func windows(from result: CopilotQuotaParser.Result) -> [UsageWindow] {
        result.windows.map { window in
            if let count = window.usedCount, let limit = window.includedLimit, limit > 0 {
                return UsageWindow(
                    id: window.id,
                    label: window.label,
                    used: count,
                    limit: limit,
                    usedPercent: window.usedPercent,
                    windowMinutes: nil,
                    resetsAt: window.resetsAt
                )
            }
            if window.displaysPercent {
                return UsageWindow(
                    id: window.id,
                    label: window.label,
                    used: Int(window.usedPercent.rounded()),
                    limit: 100,
                    usedPercent: window.usedPercent,
                    windowMinutes: nil,
                    resetsAt: window.resetsAt
                )
            }
            return UsageWindow(
                id: window.id,
                label: window.label,
                used: window.usedCount ?? 0,
                limit: 0,
                usedPercent: 0,
                windowMinutes: nil,
                resetsAt: window.resetsAt
            )
        }
    }

    private func map(_ result: CopilotQuotaParser.Result) -> UsageReading {
        let windows = Self.windows(from: result)
        let status: UsageReading.ReadingStatus
        switch result.status {
        case .live: status = .live
        case .needsAuth: status = .needsAuth
        case .unknown: status = .unknown
        case .error: status = .error(result.error ?? "Copilot account quota is unavailable from this CLI")
        }
        return UsageReading(
            providerId: id,
            label: label,
            accountId: result.accountId,
            authMode: result.authMode,
            source: result.source,
            windows: windows,
            status: status,
            observedAt: windows.isEmpty ? nil : Date(),
            error: result.error
        )
    }

    private func makeReading(status: UsageReading.ReadingStatus, error: String? = nil) -> UsageReading {
        UsageReading(
            providerId: id,
            label: label,
            accountId: nil,
            authMode: "unknown",
            source: "copilot_account_quota",
            windows: [],
            status: status,
            observedAt: nil,
            error: error
        )
    }
}
