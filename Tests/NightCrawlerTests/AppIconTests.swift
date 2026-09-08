import AppKit
import Testing

@MainActor
@Test
func applicationIconContainsUsableSmallAndRetinaRepresentations() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let icon = try #require(NSImage(contentsOf: root.appendingPathComponent("Resources/AppIcon.icns")),
                            "the app must ship a real macOS icon, not the default executable icon")
    #expect(icon.representations.contains { $0.pixelsWide >= 1024 })
    #expect(icon.representations.contains { $0.pixelsWide == 32 })
    let plist = try PropertyListSerialization.propertyList(
        from: Data(contentsOf: root.appendingPathComponent("Resources/Info.plist")), format: nil
    ) as? [String: Any]
    #expect(plist?["CFBundleIconFile"] as? String == "AppIcon")
}
