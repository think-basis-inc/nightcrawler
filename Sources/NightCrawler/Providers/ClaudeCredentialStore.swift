import Foundation

/// Reads the existing Claude Code login file directly. This avoids invoking
/// macOS Keychain tooling, so background refreshes cannot trigger a password
/// prompt. The token is validated and retained only in this actor's memory.
actor ClaudeCredentialStore {
    static let shared = ClaudeCredentialStore()
    static let maxBytes = 65_536

    typealias Reader = @Sendable (URL) -> Data?

    private let fileURL: URL
    private let reader: Reader
    private var cache: Cache?

    private enum Cache {
        case token(String)
        case unavailable
    }

    init(fileURL: URL = ClaudeCredentialStore.defaultFileURL, reader: Reader? = nil) {
        self.fileURL = fileURL
        self.reader = reader ?? ClaudeCredentialStore.defaultReader
    }

    func read() -> String? {
        switch cache {
        case .token(let token):
            return token
        case .unavailable:
            return nil
        case .none:
            break
        }

        guard let data = reader(fileURL), data.count <= Self.maxBytes,
              let token = parseToken(data)
        else {
            cache = .unavailable
            return nil
        }
        cache = .token(token)
        return token
    }

    func allowRetry() {
        cache = nil
    }

    private func parseToken(_ data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              token.range(of: #"^[A-Za-z0-9._~-]{1,16384}$"#, options: .regularExpression) != nil,
              let expires = number(oauth["expiresAt"]), expires / 1000 > Date().timeIntervalSince1970,
              let subscription = oauth["subscriptionType"] as? String, !subscription.isEmpty
        else { return nil }
        return token
    }

    private func number(_ value: Any?) -> Double? {
        if value is Bool { return nil }
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            let double = number.doubleValue
            return double.isFinite && double >= 0 ? double : nil
        }
        return nil
    }

    private static let defaultFileURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/.credentials.json")

    nonisolated private static func defaultReader(_ url: URL) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        return try? handle.read(upToCount: maxBytes + 1)
    }
}
