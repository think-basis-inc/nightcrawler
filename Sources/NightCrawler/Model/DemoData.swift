import Foundation

enum DemoData {
    static var readings: [UsageReading] {
        let now = Date()
        return [
            UsageReading(
                providerId: "claude",
                label: "Claude Code",
                accountId: "demo-claude",
                authMode: "subscription",
                source: "demo",
                windows: [
                    UsageWindow(id: "weekly_scoped", label: "Fable", used: 9200, limit: 10000, usedPercent: 92, windowMinutes: 10080, resetsAt: now.addingTimeInterval(3600)),
                    UsageWindow(id: "weekly_all", label: "All models", used: 3800, limit: 10000, usedPercent: 38, windowMinutes: 10080, resetsAt: now.addingTimeInterval(4 * 86400))
                ],
                status: .live,
                observedAt: now,
                error: nil
            ),
            UsageReading(
                providerId: "codex",
                label: "Codex CLI",
                accountId: "demo-codex",
                authMode: "subscription",
                source: "demo",
                windows: [
                    UsageWindow(id: "primary", label: "Current session", used: 900, limit: 10000, usedPercent: 9, windowMinutes: 300, resetsAt: now.addingTimeInterval(2400))
                ],
                status: .live,
                observedAt: now,
                error: nil
            ),
            UsageReading(
                providerId: "cursor",
                label: "Cursor",
                accountId: "demo-cursor",
                authMode: "subscription",
                source: "demo",
                windows: [
                    UsageWindow(id: "cursor_models", label: "Cursor Models", used: 3900, limit: 10000, usedPercent: 39, windowMinutes: 43200, resetsAt: now.addingTimeInterval(12 * 86400)),
                    UsageWindow(id: "other_models", label: "Other Models", used: 100, limit: 10000, usedPercent: 1, windowMinutes: 43200, resetsAt: now.addingTimeInterval(12 * 86400))
                ],
                status: .live,
                observedAt: now,
                error: nil
            ),
            UsageReading(
                providerId: "copilot",
                label: "GitHub Copilot",
                accountId: nil,
                authMode: "subscription",
                source: "demo",
                windows: [
                    UsageWindow(id: "premium_interactions", label: "Premium requests", used: 9800, limit: 10000, usedPercent: 98, windowMinutes: nil, resetsAt: now.addingTimeInterval(6 * 86400))
                ],
                status: .live,
                observedAt: now,
                error: nil
            ),
            UsageReading(
                providerId: "grok",
                label: "Grok",
                accountId: nil,
                authMode: "subscription",
                source: "demo",
                windows: [
                    UsageWindow(id: "credits", label: "Weekly SuperGrok Heavy Limit", used: 6500, limit: 10000, usedPercent: 65, windowMinutes: 10080, resetsAt: now.addingTimeInterval(3 * 86400)),
                    UsageWindow(id: "GrokBuild", label: "Grok Build", used: 6400, limit: 10000, usedPercent: 64, windowMinutes: 10080, resetsAt: now.addingTimeInterval(3 * 86400)),
                    UsageWindow(id: "GrokChat", label: "Grok Chat", used: 100, limit: 10000, usedPercent: 1, windowMinutes: 10080, resetsAt: now.addingTimeInterval(3 * 86400))
                ],
                status: .live,
                observedAt: now,
                error: nil
            ),
            UsageReading(
                providerId: "opencode",
                label: "OpenCode",
                accountId: nil,
                authMode: "subscription",
                source: "demo",
                windows: [
                    UsageWindow(id: "monthly", label: "Monthly limit", used: 3400, limit: 10000, usedPercent: 34, windowMinutes: 43200, resetsAt: now.addingTimeInterval(18 * 86400))
                ],
                status: .live,
                observedAt: now,
                error: nil
            ),
            UsageReading(
                providerId: "gemini",
                label: "Gemini CLI",
                accountId: nil,
                authMode: "unknown",
                source: "demo",
                windows: [],
                status: .error("Gemini CLI quota API is not currently available for individual accounts"),
                observedAt: now,
                error: nil
            )
        ]
    }
}
