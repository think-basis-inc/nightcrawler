import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: UsageStore

    private let providers = [
        ("claude", "Claude Code"),
        ("codex", "Codex CLI"),
        ("cursor", "Cursor"),
        ("copilot", "GitHub Copilot"),
        ("grok", "Grok"),
        ("gemini", "Gemini CLI"),
        ("opencode", "OpenCode"),
        ("antigravity", "Antigravity"),
        ("zcode", "ZCode / GLM"),
    ]

    var body: some View {
        Form {
            Section("Visible providers") {
                ForEach(providers, id: \.0) { id, name in
                    Toggle(name, isOn: binding(for: id))
                }
            }
        }
        .padding()
        .frame(width: 300)
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { store.enabledProviderIds.contains(id) },
            set: { isOn in
                if store.enabledProviderIds.contains(id) != isOn {
                    store.toggle(providerId: id)
                }
            }
        )
    }
}
