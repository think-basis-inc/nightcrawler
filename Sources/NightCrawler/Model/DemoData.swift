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
                    UsageWindow(id: "session", label: "Current session", used: 2500, limit: 10000, usedPercent: 25, windowMinutes: 300, resetsAt: now.addingTimeInterval(3600)),
                    UsageWindow(id: "weekly_all", label: "All models", used: 7200, limit: 10000, usedPercent: 72, windowMinutes: 10080, resetsAt: now.addingTimeInterval(4 * 86400))
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
                    UsageWindow(id: "primary", label: "Current session", used: 9100, limit: 10000, usedPercent: 91, windowMinutes: 300, resetsAt: now.addingTimeInterval(2400))
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
                    UsageWindow(id: "included", label: "Included usage", used: 4500, limit: 10000, usedPercent: 45, windowMinutes: 43200, resetsAt: now.addingTimeInterval(12 * 86400))
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
                    UsageWindow(id: "credits", label: "Grok Build", used: 1200, limit: 10000, usedPercent: 12, windowMinutes: 10080, resetsAt: now.addingTimeInterval(3 * 86400))
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
