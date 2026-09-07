import Foundation

protocol UsageProvider: Sendable {
    var id: String { get }
    var label: String { get }

    /// Whether the provider can be queried on this Mac right now.
    /// A false result means the tool is not installed or not signed in.
    var isAvailable: Bool { get }

    func read() async -> UsageReading
}
