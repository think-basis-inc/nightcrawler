import Foundation

/// Reads GitHub Copilot quota through the Copilot CLI's metadata-only
/// stdio JSON-RPC (ping → auth.getStatus → account.getQuota).
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
        let result = await CopilotRPCClient(command: command, timeout: 19).query()
        return map(result)
    }

    private func map(_ result: CopilotQuotaParser.Result) -> UsageReading {
        let windows = result.windows.map { window in
            UsageWindow(
                id: window.id,
                label: window.label,
                used: Int(window.usedPercent.rounded()),
                limit: 100,
                usedPercent: window.usedPercent,
                windowMinutes: nil,
                resetsAt: window.resetsAt
            )
        }
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
            source: "copilot_account_quota",
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
