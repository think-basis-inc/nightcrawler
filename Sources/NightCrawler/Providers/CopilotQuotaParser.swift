import Foundation

enum CopilotQuotaParser {
    struct Window: Equatable, Sendable {
        var id: String
        var label: String
        var usedPercent: Double
        var resetsAt: Date?
        var usedCount: Int? = nil
        var displaysPercent: Bool = true
    }

    struct Result: Equatable, Sendable {
        enum Status: Equatable, Sendable {
            case live, unknown, error, needsAuth
        }

        var status: Status
        var windows: [Window]
        var error: String?
        var accountId: String?
        var authMode: String
        var source: String = "copilot_account_quota"

        static func empty(
            status: Status = .unknown,
            error: String? = nil,
            accountId: String? = nil,
            authMode: String = "unknown"
        ) -> Result {
            Result(status: status, windows: [], error: error, accountId: accountId, authMode: authMode)
        }
    }

    private static let labels = [
        "premium_interactions": "Premium requests",
        "chat": "Chat requests",
        "completions": "Completions",
    ]

    static func parse(_ raw: Any) -> Result {
        guard let dict = raw as? [String: Any] else {
            return .empty(status: .error, error: "Copilot returned invalid quota metadata")
        }
        guard let snapshots = dict["quotaSnapshots"] as? [String: Any] else {
            return .empty(status: .error, error: "Copilot returned invalid quota metadata")
        }

        var windows: [Window] = []
        for (key, label) in labels {
            guard let snapshot = snapshots[key] as? [String: Any] else { continue }
            guard let limit = number(snapshot["entitlementRequests"]), limit > 0,
                  number(snapshot["usedRequests"]) != nil,
                  let remaining = number(snapshot["remainingPercentage"]),
                  remaining <= 100,
                  snapshot["isUnlimitedEntitlement"] as? Bool != true
            else { continue }
            windows.append(
                Window(
                    id: key,
                    label: label,
                    usedPercent: 100 - remaining,
                    resetsAt: epoch(snapshot["resetDate"])
                )
            )
        }

        if windows.isEmpty {
            return .empty(error: "Copilot did not report a finite subscription allowance")
        }
        return Result(status: .live, windows: windows, error: nil, accountId: nil, authMode: "unknown")
    }

    /// VS Code / `GET /copilot_internal/user` (snake_case `quota_snapshots`).
    static func parseInternalUser(_ raw: Any) -> Result {
        guard let dict = raw as? [String: Any] else {
            return .empty(status: .error, error: "Copilot returned invalid quota metadata")
        }
        guard let snapshots = dict["quota_snapshots"] as? [String: Any] else {
            return .empty(status: .error, error: "Copilot returned invalid quota metadata")
        }
        let reset = dateOnly(dict["quota_reset_date"])
            ?? epoch(dict["quota_reset_date"])
            ?? dateOnly(dict["quota_reset_date_utc"])
            ?? epoch(dict["quota_reset_date_utc"])

        var windows: [Window] = []
        for (key, label) in labels {
            guard let snapshot = snapshots[key] as? [String: Any],
                  let window = internalSnapshot(key: key, label: label, snapshot: snapshot, reset: reset)
            else { continue }
            windows.append(window)
        }

        if windows.isEmpty {
            return .empty(error: "Copilot did not report a finite subscription allowance")
        }
        return Result(
            status: .live,
            windows: windows,
            error: nil,
            accountId: nil,
            authMode: "subscription",
            source: "copilot_internal_user"
        )
    }

    static func parseBilling(_ raw: Any, planLimit: Int, now: Date) -> Result {
        guard planLimit > 0, planLimit <= 1_000_000,
              let dict = raw as? [String: Any],
              let items = dict["usageItems"] as? [[String: Any]]
        else {
            return .empty(status: .error, error: "GitHub returned invalid Copilot billing metadata")
        }

        let copilotItems = items.filter { $0["product"] as? String == "Copilot" }
        guard !copilotItems.isEmpty else {
            return .empty(
                status: .unknown,
                error: "GitHub returned no Copilot premium-request usage"
            )
        }

        let used = copilotItems.reduce(0.0) { total, item in
            guard let amount = number(item["grossQuantity"]) else { return total }
            return total + amount
        }
        guard used.isFinite else {
            return .empty(status: .error, error: "GitHub returned invalid Copilot billing metadata")
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let month = calendar.date(from: calendar.dateComponents([.year, .month], from: now))
        let reset = month.flatMap { calendar.date(byAdding: .month, value: 1, to: $0) }
        let window = Window(
            id: "premium_interactions",
            label: "Monthly premium requests",
            usedPercent: used / Double(planLimit) * 100,
            resetsAt: reset
        )
        return Result(
            status: .live,
            windows: [window],
            error: nil,
            accountId: nil,
            authMode: "subscription",
            source: "copilot_billing"
        )
    }

    private static func internalSnapshot(
        key: String,
        label: String,
        snapshot: [String: Any],
        reset: Date?
    ) -> Window? {
        let unlimited = snapshot["unlimited"] as? Bool == true
        let entitlement = number(snapshot["entitlement"]) ?? 0
        if !unlimited, entitlement > 0,
           let remaining = number(snapshot["percent_remaining"]), remaining <= 100 {
            return Window(
                id: key,
                label: label,
                usedPercent: 100 - remaining,
                resetsAt: reset ?? epoch(snapshot["reset_date"]) ?? dateOnly(snapshot["reset_date"]),
                displaysPercent: true
            )
        }
        guard key == "premium_interactions",
              let credits = number(snapshot["credits_used"])
        else { return nil }
        return Window(
            id: key,
            label: "Credits used",
            usedPercent: 0,
            resetsAt: reset ?? epoch(snapshot["reset_date"]) ?? dateOnly(snapshot["reset_date"]),
            usedCount: Int(credits.rounded()),
            displaysPercent: false
        )
    }

    private static func number(_ value: Any?) -> Double? {
        if value is Bool { return nil }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
            let double = number.doubleValue
            guard double.isFinite, double >= 0 else { return nil }
            return double
        }
        if let double = value as? Double {
            guard double.isFinite, double >= 0 else { return nil }
            return double
        }
        if let int = value as? Int, int >= 0 { return Double(int) }
        return nil
    }

    private static func epoch(_ value: Any?) -> Date? {
        guard let string = value as? String else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }

    private static func dateOnly(_ value: Any?) -> Date? {
        guard let string = value as? String, string.count == 10 else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: string)
    }
}
