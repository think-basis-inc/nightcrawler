import Foundation

enum ClaudeUsageLabels {
    static func label(for kind: String) -> String {
        switch kind {
        case "session": return "Current session"
        case "weekly_all": return "All models"
        case "weekly_scoped": return "Fable"
        case "weekly_opus": return "Opus weekly"
        case "weekly_sonnet": return "Sonnet weekly"
        default: return kind.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}
