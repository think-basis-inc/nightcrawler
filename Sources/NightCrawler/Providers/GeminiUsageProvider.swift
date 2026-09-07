import Foundation

struct GeminiUsageProvider: UsageProvider {
    let id = "gemini"
    let label = "Gemini CLI"

    var isAvailable: Bool {
        false
    }

    func read() async -> UsageReading {
        UsageReading(
            providerId: id,
            label: label,
            accountId: nil,
            authMode: "unknown",
            source: "gemini_cli_usage",
            windows: [],
            status: .error("Gemini CLI quota API is not currently available for individual accounts"),
            observedAt: nil,
            error: nil
        )
    }
}
