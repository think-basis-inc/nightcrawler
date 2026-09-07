import Foundation

enum RestrictedProcess {
    static let allowedKeys: Set<String> = ["HOME", "PATH", "LANG", "TMPDIR"]

    static func environment() -> [String: String] {
        let env = ProcessInfo.processInfo.environment
        var restricted: [String: String] = [:]
        for key in allowedKeys {
            if let value = env[key] {
                restricted[key] = value
            }
        }
        return restricted
    }

    static func executableExists(_ path: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: path)
    }

    static func resolveOnPath(_ name: String) -> String? {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for directory in path.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent(name).path
            if executableExists(candidate) { return candidate }
        }
        return nil
    }
}
