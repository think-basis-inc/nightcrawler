import Foundation

protocol UsageProvider: Sendable {
    var id: String { get }
    var label: String { get }

    func read() async throws -> UsageReading?
}
