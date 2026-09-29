import Foundation

enum ResetClock {
    static func caption(
        for date: Date,
        now: Date = Date(),
        timeZone: TimeZone = .current,
        locale: Locale = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "EEE, MMM d, h:mm a"
        _ = now
        return formatter.string(from: date)
    }
}

enum UsagePercentText {
    static func display(percent: Double, used: Int, limit: Int) -> String {
        if limit <= 0 {
            return "\(used)"
        }
        if percent > 0, percent < 0.1 {
            return "<0.1%"
        }
        return String(format: "%.1f%%", percent)
    }

    static func remaining(usedPercent: Double, used: Int, limit: Int) -> String {
        if limit <= 0 {
            return "\(used)"
        }
        let left = max(0, 100 - usedPercent)
        if usedPercent >= 100 {
            return "0.0% left"
        }
        if left > 0, left < 0.1 {
            return "<0.1% left"
        }
        return String(format: "%.1f%% left", left)
    }
}

enum UsageCaption {
    static func line(for window: UsageWindow) -> String {
        if window.limit == CopilotBusinessCredits.includedPool, window.limit > 0 {
            return "\(window.used) of \(window.limit) credits"
        }
        if window.limit <= 0 {
            return "\(window.used) credits used"
        }
        let usedText = UsagePercentText.display(
            percent: window.usedPercent,
            used: window.used,
            limit: window.limit
        )
        if window.usedPercent >= 100 {
            return "\(usedText) used"
        }
        let leftText = UsagePercentText.display(
            percent: max(0, 100 - window.usedPercent),
            used: 0,
            limit: window.limit
        )
        return "\(usedText) used · \(leftText) left"
    }
}
