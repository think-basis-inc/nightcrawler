import AppKit
import Testing
@testable import NightCrawler

@MainActor
@Test
func settingsPanelCanTakeKeyboardFocusForRepositoryEditing() throws {
    let app = NSApplication.shared
    let existing = Set(app.windows.map(ObjectIdentifier.init))
    let name = "NightCrawlerTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    let store = UsageStore(providers: [], defaults: defaults)
    store.setDemoMode(true)
    let controller = FloatingHUDController(store: store, defaults: defaults)
    controller.show()
    defer { controller.hide() }
    controller.showSettings()
    let panel = try #require(app.windows.first { !existing.contains(ObjectIdentifier($0)) })
    try #require(panel.canBecomeKey, "the repository text field must be able to receive keyboard input")
    panel.makeKeyAndOrderFront(nil)
    #expect(panel.isKeyWindow)
}
