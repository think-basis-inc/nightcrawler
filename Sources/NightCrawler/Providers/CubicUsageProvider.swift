import Foundation

/// Reads Cubic's published GitHub check report. Does not launch Cubic or request a review.
struct CubicUsageProvider: UsageProvider {
    let id = "cubic"
    let label = "Cubic"
    static let repositoryKey = "cubicUsageRepository"
    private let repository: @Sendable () -> String
    private let runner: CopilotBillingClient.Runner
    private let executable: String?
    private let now: @Sendable () -> Date

    init(repository: @escaping @Sendable () -> String = {
        UserDefaults.standard.string(forKey: Self.repositoryKey) ?? ""
    }, runner: @escaping CopilotBillingClient.Runner = CopilotBillingClient.run,
         executable: String? = RestrictedProcess.resolveOnPath("gh"),
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.repository = repository
        self.runner = runner
        self.executable = executable
        self.now = now
    }

    var isAvailable: Bool { executable != nil }

    func read() async -> UsageReading {
        await Task.detached { query() }.value
    }

    static func validRepository(_ value: String) -> Bool {
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        return parts.count == 2 && ![".", ".."].contains(String(parts[1]))
            && value.range(of: #"^[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9_.-]{1,100}$"#,
                           options: .regularExpression) != nil
    }

    private func query() -> UsageReading {
        let repo = repository()
        guard Self.validRepository(repo) else {
            return Self.empty("Choose a Cubic GitHub repository in Settings")
        }
        guard let executable else { return Self.empty("Sign in to GitHub CLI to read Cubic reports", status: .needsAuth) }
        let deadline = Date().addingTimeInterval(25)
        func get(_ endpoint: String) -> Any? {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { return nil }
            let result = runner([executable, "api", "--hostname", "github.com", "--method", "GET", endpoint],
                                min(remaining, 10), 1_048_576)
            guard result.exitCode == 0, result.stdout.count <= 1_048_576 else { return nil }
            return try? JSONSerialization.jsonObject(with: result.stdout)
        }
        // The most recently updated PR identifies the active review without reading a local checkout.
        guard let pulls = get("repos/\(repo)/pulls?state=all&sort=updated&direction=desc&per_page=1") as? [[String: Any]],
              let head = pulls.first?["head"] as? [String: Any],
              let sha = head["sha"] as? String,
              sha.range(of: #"^[a-f0-9]{40,64}$"#, options: .regularExpression) != nil else {
            return Self.empty("No accessible pull request found for Cubic usage")
        }
        var checks: [[String: Any]] = []
        for page in 1...3 {
            guard let raw = get("repos/\(repo)/commits/\(sha)/check-runs?per_page=100&page=\(page)") as? [String: Any],
                  let rows = raw["check_runs"] as? [[String: Any]] else {
                return Self.empty("GitHub could not return Cubic check reports")
            }
            checks += rows
            if rows.count < 100 { return Self.parse(checks, repository: repo, now: now()) }
        }
        return Self.empty("Cubic check history exceeded the safe query limit")
    }

    static func parse(_ checks: [[String: Any]], repository: String, now: Date = Date()) -> UsageReading {
        let candidates = checks.compactMap { check -> (Date, [String: Any])? in
            guard let app = check["app"] as? [String: Any], app["id"] as? Int == 1_082_092,
                  app["slug"] as? String == "cubic-dev-ai",
                  check["name"] as? String == "cubic · AI code reviewer",
                  check["status"] as? String == "completed",
                  let date = ProviderHelpers.parseISO8601(check["completed_at"] as? String), date <= now else { return nil }
            return (date, check)
        }
        guard let (observed, check) = candidates.max(by: { $0.0 < $1.0 }),
              let output = check["output"] as? [String: Any],
              let summary = output["summary"] as? String, summary.utf8.count <= 65_536 else {
            return empty("No completed Cubic allowance report found")
        }
        let count = #"(?:0|[1-9][0-9]{0,11}|[1-9][0-9]{0,2}(?:,[0-9]{3}){1,3})"#
        let pattern = "cubic has reviewed (\(count)) of the (\(count)) allowed lines of code this month\\. Reviews resume on ([0-9]{1,2} [A-Za-z]+ [0-9]{4})"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: summary, range: NSRange(summary.startIndex..., in: summary)) else {
            return empty("The latest Cubic check did not report a numeric allowance")
        }
        func capture(_ index: Int) -> String {
            Range(match.range(at: index), in: summary).map { String(summary[$0]) } ?? ""
        }
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = TimeZone(secondsFromGMT: 0)
        format.dateFormat = "d MMMM yyyy"
        format.isLenient = false
        guard let used = Int(capture(1).replacingOccurrences(of: ",", with: "")),
              let limit = Int(capture(2).replacingOccurrences(of: ",", with: "")), limit > 0,
              Double(used) / Double(limit) <= 10,
              let reset = format.date(from: capture(3)), reset > now, reset > observed else {
            return empty("Previous Cubic allowance report expired or was invalid")
        }
        let owner = String(repository.split(separator: "/").first ?? "")
        return UsageReading(providerId: "cubic", label: "Cubic", accountId: ProviderHelpers.sha256Prefix(owner.lowercased()),
            authMode: "github", source: "cubic_github_check", windows: [UsageWindow(
                id: "reviewed_lines", label: "Last reported lines", used: used, limit: limit,
                usedPercent: Double(used) / Double(limit) * 100, windowMinutes: nil, resetsAt: reset
            )], status: .live, observedAt: observed, error: "Last reported by Cubic; not a live balance")
    }

    private static func empty(_ message: String, status: UsageReading.ReadingStatus = .unknown) -> UsageReading {
        UsageReading(providerId: "cubic", label: "Cubic", accountId: nil, authMode: "github",
            source: "cubic_github_check", windows: [], status: status, observedAt: nil, error: message)
    }
}
