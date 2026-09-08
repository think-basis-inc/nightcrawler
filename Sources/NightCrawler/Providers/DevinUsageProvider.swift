import Foundation

struct DevinUsageProvider: UsageProvider {
    let id = "devin"
    let label = "Devin"
    private let credentialURL: URL
    private let loader: QuotaHTTP.Loader
    private let versionReader: @Sendable () -> String?

    init(credentialURL: URL? = nil, loader: @escaping QuotaHTTP.Loader = QuotaHTTP.load,
         versionReader: @escaping @Sendable () -> String? = Self.cliVersion) {
        let dataHome = ProcessInfo.processInfo.environment["XDG_DATA_HOME"]
        let root = dataHome.flatMap { $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : nil }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/share")
        self.credentialURL = credentialURL ?? root.appendingPathComponent("devin/credentials.toml")
        self.loader = loader
        self.versionReader = versionReader
    }

    var isAvailable: Bool { FileManager.default.fileExists(atPath: credentialURL.path) }

    func read() async -> UsageReading {
        guard let handle = try? FileHandle(forReadingFrom: credentialURL) else {
            return Self.empty(.needsAuth, "Sign in to Devin CLI to read usage")
        }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 65_537), let token = Self.credential(from: data) else {
            return Self.empty(.needsAuth, "Supported Devin CLI login unavailable")
        }
        guard let version = await Task.detached(operation: versionReader).value else {
            return Self.empty(.unknown, "Could not read the installed Devin CLI version")
        }
        var request = URLRequest(url: URL(string:
            "https://server.codeium.com/exa.seat_management_pb.SeatManagementService/GetUserStatus")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["metadata": [
            "apiKey": token, "ideName": "devin", "ideVersion": version,
            "extensionVersion": version, "locale": "en"
        ]])
        do {
            let (body, response) = try await loader(request)
            if [401, 403].contains(response.statusCode) {
                return Self.empty(.needsAuth, "Devin login expired; sign in through Devin CLI")
            }
            guard response.statusCode == 200, body.count <= 1_048_576 else {
                return Self.empty(.error("Devin quota request failed"), "Devin quota request failed")
            }
            return Self.parse(body)
        } catch {
            return Self.empty(.error("Devin quota unavailable"), "Devin quota request failed or timed out")
        }
    }

    // Accept the CLI's two top-level scalar fields, not arbitrary TOML config or origins.
    // Unexpected encodings fail closed; never log credential data or parser errors.
    static func credential(from data: Data) -> String? {
        guard data.count <= 65_536, let text = String(data: data, encoding: .utf8) else { return nil }
        var fields: [String: String] = [:]
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") { break }
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, ["api_server_url", "windsurf_api_key"].contains(parts[0]) else { continue }
            guard fields[parts[0]] == nil else { return nil }
            let value: String?
            if parts[1].hasPrefix("'"), parts[1].hasSuffix("'") {
                value = String(parts[1].dropFirst().dropLast())
            } else {
                value = try? JSONDecoder().decode(String.self, from: Data(parts[1].utf8))
            }
            guard let value else { return nil }
            fields[parts[0]] = value
        }
        guard fields["api_server_url"] == "https://server.codeium.com",
              let token = fields["windsurf_api_key"], (1...16_384).contains(token.utf8.count),
              token.utf8.allSatisfy({ (33...126).contains($0) }) else { return nil }
        return token
    }

    static func parse(_ data: Data, now: Date = Date()) -> UsageReading {
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let user = raw["userStatus"] as? [String: Any],
              let plan = user["planStatus"] as? [String: Any],
              let info = (raw["planInfo"] ?? plan["planInfo"]) as? [String: Any],
              info["billingStrategy"] as? String == "BILLING_STRATEGY_QUOTA" else {
            return empty(.unknown, "Devin did not report a subscription quota")
        }
        let windows = [("daily", 1440), ("weekly", 10080)].compactMap { period, minutes -> UsageWindow? in
            guard let remaining = number(plan[period + "QuotaRemainingPercent"]), (0...100).contains(remaining) else { return nil }
            let reset = number(plan[period + "QuotaResetAtUnix"])
                .flatMap { (1...253_402_300_799).contains($0) ? Date(timeIntervalSince1970: $0) : nil }
            return UsageWindow(id: period, label: period.capitalized + " quota", used: Int((100 - remaining) * 100),
                limit: 10_000, usedPercent: 100 - remaining, windowMinutes: minutes, resetsAt: reset)
        }
        guard !windows.isEmpty else { return empty(.unknown, "Devin did not report daily or weekly quota") }
        let identity = (user["userId"] as? String).map { ProviderHelpers.sha256Prefix($0) }
        return UsageReading(providerId: "devin", label: "Devin", accountId: identity,
            authMode: "subscription", source: "devin_user_status", windows: windows,
            status: .live, observedAt: now, error: nil)
    }

    private static func number(_ raw: Any?) -> Double? {
        if let number = raw as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
        let value = (raw as? NSNumber)?.doubleValue ?? (raw as? String).flatMap(Double.init)
        return value.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
    }

    static func cliVersion() -> String? {
        guard let executable = RestrictedProcess.resolveOnPath("devin") else { return nil }
        let result = CopilotBillingClient.run([executable, "version"], timeout: 5, maxBytes: 1024)
        guard result.exitCode == 0, let text = String(data: result.stdout, encoding: .utf8),
              let match = text.range(of: #"(?<=^devin )[0-9]+\.[0-9]+\.[0-9]+"#, options: .regularExpression) else { return nil }
        return String(text[match])
    }

    private static func empty(_ status: UsageReading.ReadingStatus, _ message: String) -> UsageReading {
        UsageReading(providerId: "devin", label: "Devin", accountId: nil, authMode: "unknown",
            source: "devin_user_status", windows: [], status: status, observedAt: nil, error: message)
    }
}
