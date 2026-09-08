import Foundation

struct ProviderCatalogItem: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
}

struct RoutingToolState: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let label: String
    var enabled: Bool
    var available: Bool

    static let defaults = [
        RoutingToolState(id: "devin", label: "Devin", enabled: true, available: true),
        RoutingToolState(id: "cubic", label: "Cubic", enabled: false, available: false),
    ]
}
