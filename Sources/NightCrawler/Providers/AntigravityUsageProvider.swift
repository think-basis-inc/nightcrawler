import Foundation

/// Reads Antigravity usage from Google's Cloud Code backend using the OAuth
/// token Antigravity stores in the macOS Keychain.
///
/// For accounts with a published quota, the monitor endpoint returns windows.
/// Personal accounts receive 403, which is reported honestly rather than
/// inventing a limit.
struct AntigravityUsageProvider: UsageProvider {
    let id = "antigravity"
    let label = "Antigravity"

    private static let keychainService = "gemini"
    private static let keychainAccount = "antigravity"
    private static let goKeyringPrefix = "go-keyring-base64:"
    private static let loadEndpoint = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist")!
    private static let quotaEndpoint = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary")!

    var isAvailable: Bool {
        // Disabled by default to avoid keychain prompts. Enable in Settings once
        // you are ready to grant access to Antigravity's stored credential.
        false
    }

    func read() async -> UsageReading {
        guard let credentials = loadCredentials() else {
            return makeReading(status: .needsAuth, error: "Sign in to Antigravity to enable usage reading")
        }
        guard !credentials.isExpired else {
            return makeReading(status: .needsAuth, error: "Antigravity login expired; sign in again")
        }

        do {
            let _ = try await post(url: Self.loadEndpoint, token: credentials.accessToken, body: ["metadata": ["pluginType": "GEMINI"]])
            let quota = try await post(url: Self.quotaEndpoint, token: credentials.accessToken, body: [:])

            guard let data = quota,
                  let windows = windows(from: data), !windows.isEmpty
            else {
                return makeReading(status: .error("Antigravity does not publish a usage quota for this account"))
            }

            return UsageReading(
                providerId: id,
                label: label,
                accountId: nil,
                authMode: "subscription",
                source: "antigravity_usage",
                windows: windows,
                status: .live,
                observedAt: Date(),
                error: nil
            )
        } catch ProviderError.needsAuth {
            return makeReading(status: .needsAuth, error: "Antigravity login expired")
        } catch ProviderError.rateLimited {
            return makeReading(status: .error("Rate limited by Antigravity"))
        } catch {
            return makeReading(status: .error("Antigravity usage request failed"))
        }
    }

    private func post(url: URL, token: String, body: [String: Any]) async throws -> Data? {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.badResponse
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw ProviderError.needsAuth
        }
        if http.statusCode == 429 {
            throw ProviderError.rateLimited
        }
        guard http.statusCode == 200 else {
            throw ProviderError.badResponse
        }
        return data
    }

    private func windows(from data: Data) -> [UsageWindow]? {
        struct Response: Decodable {
            struct Bucket: Decodable {
                let name: String?
                let displayName: String?
                let used: Double?
                let limit: Double?
                let resetTime: String?
            }
            struct Group: Decodable {
                let displayName: String?
                let buckets: [Bucket]?
            }
            let quotaGroups: [Group]?
            let buckets: [Bucket]?
        }

        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else { return nil }
        let allBuckets = (decoded.quotaGroups?.flatMap { $0.buckets ?? [] } ?? []) + (decoded.buckets ?? [])

        return allBuckets.compactMap { bucket in
            guard let limit = bucket.limit, limit > 0,
                  let used = bucket.used, used >= 0
            else { return nil }
            let label = bucket.displayName ?? bucket.name ?? "Usage"
            return UsageWindow(
                id: bucket.name ?? label,
                label: label,
                used: Int(used),
                limit: Int(limit),
                usedPercent: (used / limit) * 100,
                windowMinutes: nil,
                resetsAt: ProviderHelpers.parseRFC3339(bucket.resetTime)
            )
        }
    }

    private func loadCredentials() -> Credentials? {
        guard let data = Keychain.readPasswordData(service: Self.keychainService, account: Self.keychainAccount),
              let decoded = decode(data)
        else { return nil }
        return decoded
    }

    private func decode(_ data: Data) -> Credentials? {
        guard var text = String(data: data, encoding: .utf8) else { return nil }
        if text.hasPrefix(Self.goKeyringPrefix) {
            text = String(text.dropFirst(Self.goKeyringPrefix.count))
        }
        guard let payload = Data(base64Encoded: text),
              let root = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let authMethod = root["auth_method"] as? String,
              let tokenDict = root["token"] as? [String: Any],
              let accessToken = tokenDict["access_token"] as? String, !accessToken.isEmpty,
              let expiry = tokenDict["expiry"] as? String,
              let expiresAt = ProviderHelpers.parseRFC3339(expiry)
        else { return nil }

        return Credentials(accessToken: accessToken, expiresAt: expiresAt, authMethod: authMethod)
    }

    private func makeReading(status: UsageReading.ReadingStatus, error: String? = nil) -> UsageReading {
        UsageReading(
            providerId: id,
            label: label,
            accountId: nil,
            authMode: "unknown",
            source: "antigravity_usage",
            windows: [],
            status: status,
            observedAt: nil,
            error: error
        )
    }

    private enum ProviderError: Error {
        case needsAuth
        case rateLimited
        case badResponse
    }

    private struct Credentials {
        let accessToken: String
        let expiresAt: Date
        let authMethod: String

        var isExpired: Bool { expiresAt <= Date() }
    }
}
