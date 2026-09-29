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
        let owner = String(repo.split(separator: "/").first ?? "")
        let deadline = Date().addingTimeInterval(25)
        func run(_ args: [String]) -> Any? {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { return nil }
            let result = runner([executable] + args, min(remaining, 10), 1_048_576)
            guard result.exitCode == 0, result.stdout.count <= 1_048_576 else { return nil }
            return try? JSONSerialization.jsonObject(with: result.stdout)
        }
        // Org-wide: Cubic's line allowance is shared, and the configured repo may
        // not have the newest check after a billing-period reset.
        let graphQuery = "query($q:String!){ search(query:$q, type:ISSUE, first:15){ nodes { ... on PullRequest { commits(last:1){ nodes { commit { checkSuites(first:20, filterBy:{appId:1082092}){ nodes { app { databaseId slug } checkRuns(first:10){ nodes { name status completedAt conclusion summary title } } } } } } } } } } }"
        if let raw = run([
            "api", "--hostname", "github.com", "graphql",
            "-f", "query=\(graphQuery)",
            "-f", "q=org:\(owner) is:pr sort:updated",
        ]), let checks = Self.checks(fromGraphQL: raw), !checks.isEmpty {
            return Self.parse(checks, repository: repo, now: now())
        }
        func get(_ endpoint: String) -> Any? {
            run(["api", "--hostname", "github.com", "--method", "GET", endpoint])
        }
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
        let candidates = checks.compactMap { authenticCheck($0, now: now) }
        guard let newest = candidates.max(by: { $0.0 < $1.0 }) else {
            return empty("No completed Cubic allowance report found")
        }
        let quotas = candidates.compactMap { quota(from: $0.1, observed: $0.0, now: now) }
        if let live = quota(from: newest.1, observed: newest.0, now: now), live.reset > now {
            return reading(from: live, repository: repository, used: live.used, error: "Last reported by Cubic; not a live balance")
        }
        if let previous = quotas.max(by: { $0.observed < $1.observed }), previous.reset <= now {
            if let resumed = candidates.filter({ isCompletedAIReview($0.1) && $0.0 > previous.reset }).max(by: { $0.0 < $1.0 }),
               let nextReset = nextBillingReset(after: previous.reset), nextReset > now {
                return reading(
                    from: Quota(used: 0, limit: previous.limit, reset: nextReset, observed: resumed.0),
                    repository: repository,
                    used: 0,
                    error: "Cubic resumed reviews without publishing a new line count"
                )
            }
            return empty("Previous Cubic allowance report expired or was invalid")
        }
        return empty("The latest Cubic check did not report a numeric allowance")
    }

    private static func authenticCheck(_ check: [String: Any], now: Date) -> (Date, [String: Any])? {
        guard let app = check["app"] as? [String: Any], int(app["id"]) == 1_082_092,
              app["slug"] as? String == "cubic-dev-ai",
              check["name"] as? String == "cubic · AI code reviewer",
              (check["status"] as? String)?.lowercased() == "completed",
              let date = ProviderHelpers.parseISO8601(check["completed_at"] as? String), date <= now
        else { return nil }
        return (date, check)
    }

    private struct Quota {
        var used: Int
        var limit: Int
        var reset: Date
        var observed: Date
    }

    private static func quota(from check: [String: Any], observed: Date, now: Date) -> Quota? {
        guard let output = check["output"] as? [String: Any],
              let summary = output["summary"] as? String, summary.utf8.count <= 65_536,
              observed <= now else { return nil }
        let count = #"(?:0|[1-9][0-9]{0,11}|[1-9][0-9]{0,2}(?:,[0-9]{3}){1,3})"#
        let pattern = "cubic has reviewed (\(count)) of the (\(count)) allowed lines of code this month\\. Reviews resume on ([0-9]{1,2} [A-Za-z]+ [0-9]{4})"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: summary, range: NSRange(summary.startIndex..., in: summary)) else {
            return nil
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
              let reset = format.date(from: capture(3)), reset > observed else {
            return nil
        }
        return Quota(used: used, limit: limit, reset: reset, observed: observed)
    }

    private static func isCompletedAIReview(_ check: [String: Any]) -> Bool {
        let output = check["output"] as? [String: Any]
        let summary = output?["summary"] as? String ?? ""
        let title = output?["title"] as? String ?? ""
        return title == "AI review completed" || summary.hasPrefix("AI review completed")
    }

    private static func nextBillingReset(after reset: Date) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(byAdding: .month, value: 1, to: reset)
    }

    private static func reading(from quota: Quota, repository: String, used: Int, error: String) -> UsageReading {
        let owner = String(repository.split(separator: "/").first ?? "")
        let percent = Double(used) / Double(quota.limit) * 100
        return UsageReading(
            providerId: "cubic", label: "Cubic",
            accountId: ProviderHelpers.sha256Prefix(owner.lowercased()),
            authMode: "github", source: "cubic_github_check",
            windows: [UsageWindow(
                id: "reviewed_lines", label: "Last reported lines",
                used: used, limit: quota.limit, usedPercent: percent,
                windowMinutes: nil, resetsAt: quota.reset
            )],
            status: .live, observedAt: quota.observed, error: error
        )
    }

    private static func checks(fromGraphQL raw: Any) -> [[String: Any]]? {
        guard let root = raw as? [String: Any], root["errors"] == nil,
              let search = (root["data"] as? [String: Any])?["search"] as? [String: Any],
              let nodes = search["nodes"] as? [Any] else { return nil }
        var checks: [[String: Any]] = []
        for node in nodes {
            guard let pull = node as? [String: Any] else { continue }
            let commitNodes = ((pull["commits"] as? [String: Any])?["nodes"] as? [[String: Any]]) ?? []
            for commitNode in commitNodes {
                let suites = (((commitNode["commit"] as? [String: Any])?["checkSuites"] as? [String: Any])?["nodes"] as? [[String: Any]]) ?? []
                for suite in suites {
                    let app = suite["app"] as? [String: Any]
                    let runs = ((suite["checkRuns"] as? [String: Any])?["nodes"] as? [[String: Any]]) ?? []
                    for run in runs {
                        checks.append([
                            "app": [
                                "id": int(app?["databaseId"]) ?? 0,
                                "slug": app?["slug"] as? String ?? "",
                            ],
                            "name": run["name"] as? String ?? "",
                            "status": (run["status"] as? String)?.lowercased() ?? "",
                            "completed_at": run["completedAt"] as? String ?? "",
                            "conclusion": (run["conclusion"] as? String)?.lowercased() ?? "",
                            "output": [
                                "summary": run["summary"] as? String ?? "",
                                "title": run["title"] as? String ?? "",
                            ],
                        ])
                    }
                }
            }
        }
        return checks
    }

    private static func int(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }

    private static func empty(_ message: String, status: UsageReading.ReadingStatus = .unknown) -> UsageReading {
        UsageReading(providerId: "cubic", label: "Cubic", accountId: nil, authMode: "github",
            source: "cubic_github_check", windows: [], status: status, observedAt: nil, error: message)
    }
}
