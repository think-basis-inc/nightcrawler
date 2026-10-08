import Foundation
import Security

enum Keychain {
    static func readPassword(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func readGenericPassword(service: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    enum Lookup: Equatable {
        case found(Data)
        case missing
        /// The user denied or dismissed the access prompt; asking again
        /// raises the same system dialog.
        case denied
        /// The keychain is locked or cannot prompt right now; retry later.
        case unavailable
    }

    static func lookupPasswordData(service: String, account: String) -> Lookup {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data { return .found(data) }
        return outcome(for: status)
    }

    static func outcome(for status: OSStatus) -> Lookup {
        switch status {
        case errSecAuthFailed, errSecUserCanceled: return .denied
        case errSecInteractionNotAllowed: return .unavailable
        default: return .missing
        }
    }
}
