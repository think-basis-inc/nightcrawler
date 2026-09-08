import Foundation

final class HUDDisplayPreferences {
    private enum Key {
        static let miniMode = "hudMiniModeEnabled"
        static let autoHide = "hudAutoHideEnabled"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isMiniModeEnabled: Bool { defaults.bool(forKey: Key.miniMode) }
    var isAutoHideEnabled: Bool { defaults.bool(forKey: Key.autoHide) }
    var railScale: CGFloat { isMiniModeEnabled ? HUDLayout.compactRailScale : 1 }

    func setMiniModeEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Key.miniMode)
    }

    func setAutoHideEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Key.autoHide)
    }
}
