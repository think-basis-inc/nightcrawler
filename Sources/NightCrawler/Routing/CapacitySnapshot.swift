import Foundation

struct CapacitySnapshot: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let generatedAt: Date
    let resources: [CapacityResource]

    @MainActor
    static func make(from store: UsageStore, now: Date = Date()) -> CapacitySnapshot {
        let readings = Dictionary(uniqueKeysWithValues: store.readings.map { ($0.providerId, $0) })
        var resources = store.providerCatalog.enumerated().map { index, provider in
            CapacityResource(
                id: provider.id,
                label: provider.label,
                kind: .usageProvider,
                priority: index,
                enabled: store.enabledProviderIds.contains(provider.id),
                available: availability(for: readings[provider.id]),
                capacity: capacity(for: readings[provider.id], now: now)
            )
        }

        resources.append(contentsOf: store.routingToolStates.enumerated().map { index, tool in
            CapacityResource(
                id: tool.id,
                label: tool.label,
                kind: .routingTool,
                priority: index,
                enabled: tool.enabled,
                available: tool.available ? .available : .unavailable,
                capacity: CapacityState(
                    status: .unknown,
                    freshness: .unknown,
                    observedAt: nil,
                    windows: [],
                    message: "No authoritative quota source"
                )
            )
        })

        return CapacitySnapshot(schemaVersion: 1, generatedAt: now, resources: resources)
    }

    private static func availability(for reading: UsageReading?) -> ResourceAvailability {
        guard let reading else { return .unknown }
        switch reading.status {
        case .live, .unknown: return .available
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
            freshness = now.timeIntervalSince(observedAt) <= 120 ? .fresh : .stale
        } else {
            freshness = .unknown
        }
        return CapacityState(
            status: status,
            freshness: freshness,
            observedAt: reading.observedAt,
            windows: reading.windows.map {
                CapacityWindow(
                    id: $0.id,
                    label: $0.label,
                    usedPercent: $0.usedPercent,
                    resetsAt: $0.resetsAt
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
}
