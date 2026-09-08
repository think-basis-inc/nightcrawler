import Foundation

struct CapacitySnapshot: Codable, Equatable, Sendable {
    static let liveFreshnessInterval: TimeInterval = 120
    let schemaVersion: Int
    let generatedAt: Date
    let resources: [CapacityResource]

    @MainActor
    static func make(from store: UsageStore, now: Date = Date()) -> CapacitySnapshot {
        let readings = Dictionary(
            store.readings.map { ($0.providerId, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        let routingTools = Dictionary(
            store.routingToolStates.map { ($0.id, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        let resources = store.providerCatalog.enumerated().map { index, provider in
            let tool = routingTools[provider.id]
            return CapacityResource(
                id: provider.id,
                label: provider.label,
                kind: tool == nil ? .usageProvider : .routingTool,
                priority: index,
                enabled: tool?.enabled ?? store.enabledProviderIds.contains(provider.id),
                available: tool.map {
                    $0.available ? .available : .unavailable
                } ?? availability(for: readings[provider.id], now: now),
                capacity: capacity(for: readings[provider.id], now: now)
            )
        }

        return CapacitySnapshot(schemaVersion: 1, generatedAt: now, resources: resources)
    }

    private static func availability(for reading: UsageReading?, now: Date) -> ResourceAvailability {
        guard let reading else { return .unknown }
        switch reading.status {
        case .live:
            guard let observedAt = reading.observedAt else { return .unknown }
            return now.timeIntervalSince(observedAt) <= liveFreshnessInterval ? .available : .unknown
        case .unknown: return .available
        case .needsAuth, .error: return .unavailable
        }
    }

    private static func capacity(for reading: UsageReading?, now: Date) -> CapacityState {
        guard let reading else {
            return CapacityState(
                status: .unknown,
                freshness: .unknown,
                observedAt: nil,
                windows: [],
                message: "No recent reading"
            )
        }

        let status: CapacityStatus
        switch reading.status {
        case .live: status = .live
        case .unknown: status = .unknown
        case .needsAuth: status = .unavailable
        case .error: status = .error
        }
        let freshness: CapacityFreshness
        if let observedAt = reading.observedAt {
            freshness = now.timeIntervalSince(observedAt) <= liveFreshnessInterval ? .fresh : .stale
        } else {
            freshness = .unknown
        }
        return CapacityState(
            status: status,
            freshness: freshness,
            observedAt: reading.observedAt,
            windows: reading.windows.map { window in
                let observedAt = window.observedAt ?? reading.observedAt
                let freshness: CapacityFreshness
                if let observedAt {
                    freshness = now.timeIntervalSince(observedAt) <= liveFreshnessInterval ? .fresh : .stale
                } else {
                    freshness = .unknown
                }
                return CapacityWindow(
                    id: window.id,
                    label: window.label,
                    usedPercent: window.usedPercent,
                    resetsAt: window.resetsAt,
                    observedAt: observedAt,
                    freshness: freshness
                )
            },
            message: reading.error
        )
    }
}

struct CapacityResource: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case usageProvider = "usage_provider"
        case routingTool = "routing_tool"
    }

    let id: String
    let label: String
    let kind: Kind
    let priority: Int
    let enabled: Bool
    let available: ResourceAvailability
    let capacity: CapacityState
}

enum ResourceAvailability: String, Codable, Sendable {
    case available
    case unavailable
    case unknown
}

struct CapacityState: Codable, Equatable, Sendable {
    let status: CapacityStatus
    let freshness: CapacityFreshness
    let observedAt: Date?
    let windows: [CapacityWindow]
    let message: String?
}

enum CapacityStatus: String, Codable, Sendable {
    case live
    case unknown
    case unavailable
    case error
}

enum CapacityFreshness: String, Codable, Sendable {
    case fresh
    case stale
    case unknown
}

struct CapacityWindow: Codable, Equatable, Sendable {
    let id: String
    let label: String
    let usedPercent: Double
    let resetsAt: Date?
    let observedAt: Date?
    let freshness: CapacityFreshness
}
