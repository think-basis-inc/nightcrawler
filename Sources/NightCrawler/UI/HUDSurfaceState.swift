import Foundation

struct HUDSurfaceState: Equatable {
    enum Mode: Equatable {
        case idle
        case detail(providerId: String)
        case settings
    }

    var mode: Mode = .idle

    var usesSeparateWindow: Bool { false }

    var selectedProviderId: String? {
        if case .detail(let id) = mode { return id }
        return nil
    }

    mutating func selectProvider(_ id: String) {
        if selectedProviderId == id {
            mode = .idle
        } else {
            mode = .detail(providerId: id)
        }
    }

    mutating func toggleSettings() {
        mode = mode == .settings ? .idle : .settings
    }

    mutating func dismiss() {
        mode = .idle
    }

    mutating func preserveAcrossRefresh() {}
}
