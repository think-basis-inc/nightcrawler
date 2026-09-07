import Cocoa
import os.log
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = UsageStore()
    private var hud: FloatingHUDController?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        if ProcessInfo.processInfo.environment["NIGHTCRAWLER_DEMO"] == "1" || DemoState.isEnabled {
            store.readings = DemoData.readings
        }

        let hud = FloatingHUDController(store: store)
        hud.show()
        self.hud = hud

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "gauge.with.dots.needle.67percent", accessibilityDescription: "NightCrawler")
        statusItem.menu = makeMenu()
        self.statusItem = statusItem

        let isDemo = ProcessInfo.processInfo.environment["NIGHTCRAWLER_DEMO"] == "1" || DemoState.isEnabled
        store.startPolling(skipInitialPoll: isDemo)
    }

    func applicationWillTerminate(_ notification: Notification) {
        hud?.hide()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Move HUD", action: #selector(cycleEdge), keyEquivalent: "m"))
        menu.addItem(NSMenuItem(title: "Refresh", action: #selector(refresh), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Demo mode", action: #selector(toggleDemoMode), keyEquivalent: "d"))
        menu.addItem(NSMenuItem(title: "Launch at login", action: #selector(toggleLaunchAtLogin), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit NightCrawler", action: #selector(quit), keyEquivalent: "q"))
        updateLaunchAtLoginState(in: menu)
        updateDemoModeState(in: menu)
        return menu
    }

    @objc private func cycleEdge() {
        hud?.cycleEdge()
    }

    @objc private func refresh() {
        Task { await store.refresh() }
    }

    @objc private func toggleDemoMode(_ sender: NSMenuItem) {
        let isDemo = !DemoState.isEnabled
        DemoState.isEnabled = isDemo
        store.readings = isDemo ? DemoData.readings : []
        sender.state = isDemo ? .on : .off
    }

    @objc private func showSettings() {
        hud?.showSettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Launch at login

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            os_log("Failed to toggle launch at login: %{public}@", error.localizedDescription)
        }
        updateLaunchAtLoginState(in: sender.menu)
    }

    private func updateLaunchAtLoginState(in menu: NSMenu?) {
        guard let item = menu?.items.first(where: { $0.action == #selector(toggleLaunchAtLogin) }) else { return }
        item.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    private func updateDemoModeState(in menu: NSMenu?) {
        guard let item = menu?.items.first(where: { $0.action == #selector(toggleDemoMode) }) else { return }
        item.state = DemoState.isEnabled ? .on : .off
    }
}

@MainActor
enum DemoState {
    @UserDefault("demoMode", defaultValue: false)
    static var isEnabled: Bool
}

@propertyWrapper
struct UserDefault<T> {
    let key: String
    let defaultValue: T

    var wrappedValue: T {
        get { UserDefaults.standard.object(forKey: key) as? T ?? defaultValue }
        nonmutating set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    init(_ key: String, defaultValue: T) {
        self.key = key
        self.defaultValue = defaultValue
    }
}
