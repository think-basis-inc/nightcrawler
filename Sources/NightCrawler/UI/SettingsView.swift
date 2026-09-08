import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: UsageStore
    let edge: NotchEdge
    let isMiniModeEnabled: Bool
    let isAutoHideEnabled: Bool
    let onEdgeChange: (NotchEdge) -> Void
    let onMiniModeChange: (Bool) -> Void
    let onAutoHideChange: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Screen edge")
                .font(Typography.cardTitle)
                .frame(height: HUDLayout.settingsTitleHeight)
                .foregroundStyle(Palette.textPrimary)

            EdgePicker(edge: edge, onSelect: onEdgeChange)
                .padding(.top, HUDLayout.headerToBlock)

            Text("Display")
                .font(Typography.cardTitle)
                .frame(height: HUDLayout.settingsTitleHeight)
                .foregroundStyle(Palette.textPrimary)
                .padding(.top, 2 * HUDLayout.blockSpacing)

            SettingsToggleRow(
                title: "Mini mode",
                detail: "70% tab · expands on hover",
                isOn: isMiniModeEnabled,
                onToggle: { onMiniModeChange(!isMiniModeEnabled) }
            )
            .padding(.top, HUDLayout.headerToBlock)

            SettingsToggleRow(
                title: "Auto-hide",
                detail: "Edge hover · ⌥⌘N",
                isOn: isAutoHideEnabled,
                onToggle: { onAutoHideChange(!isAutoHideEnabled) }
            )
            .padding(.top, HUDLayout.settingsRowSpacing)

            Text("Visible providers")
                .font(Typography.cardTitle)
                .frame(height: HUDLayout.settingsTitleHeight)
                .foregroundStyle(Palette.textPrimary)
                .padding(.top, 2 * HUDLayout.blockSpacing)

            ForEach(Array(store.providerCatalog.enumerated()), id: \.element.id) { index, provider in
                SettingsProviderRow(
                    id: provider.id,
                    name: provider.label,
                    isOn: store.isProviderEnabled(provider.id),
                    canMoveUp: index > 0,
                    canMoveDown: index < store.providerCatalog.count - 1,
                    onToggle: { store.toggle(providerId: provider.id) },
                    onMoveUp: { store.moveProvider(provider.id, by: -1) },
                    onMoveDown: { store.moveProvider(provider.id, by: 1) }
                )
                .padding(.top, index == 0 ? HUDLayout.headerToBlock : HUDLayout.settingsRowSpacing)
            }

            Text("Copilot plan")
                .font(Typography.cardTitle)
                .frame(height: HUDLayout.settingsTitleHeight)
                .foregroundStyle(Palette.textPrimary)
                .padding(.top, 2 * HUDLayout.blockSpacing)

            CopilotPlanPicker(
                selectedLimit: store.copilotPlanLimit,
                onSelect: store.setCopilotPlanLimit
            )
            .padding(.top, HUDLayout.headerToBlock)

            if !store.routingToolStates.isEmpty {
                Text("Agent availability")
                    .font(Typography.cardTitle)
                    .frame(height: HUDLayout.settingsTitleHeight)
                    .foregroundStyle(Palette.textPrimary)
                    .padding(.top, 2 * HUDLayout.blockSpacing)

                ForEach(Array(store.routingToolStates.enumerated()), id: \.element.id) { index, tool in
                    RoutingToolRow(
                        tool: tool,
                        onToggleAvailability: { store.toggleRoutingToolAvailability(tool.id) }
                    )
                    .padding(.top, index == 0 ? HUDLayout.headerToBlock : HUDLayout.settingsRowSpacing)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(Palette.textPrimary)
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let detail: String
    let isOn: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: HUDLayout.headerGap) {
                Text(title)
                    .font(Typography.cardBody)
                    .foregroundStyle(Palette.textPrimary)
                Text(detail)
                    .font(Typography.cardBody)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                BespokeSwitch(isOn: isOn)
            }
            .frame(height: HUDLayout.settingsRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

private struct CopilotPlanPicker: View {
    let selectedLimit: Int
    let onSelect: (Int) -> Void

    private let choices = [("Free", 50), ("Pro", 300), ("Pro+", 1_500)]

    var body: some View {
        HStack(spacing: Design.px(12)) {
            ForEach(choices, id: \.1) { choice in
                Button(action: { onSelect(choice.1) }) {
                    Text("\(choice.0) · \(choice.1)")
                        .font(Typography.cardBody)
                        .foregroundStyle(selectedLimit == choice.1 ? Color.white : Palette.textSecondary)
                        .padding(.horizontal, Design.px(13))
                        .frame(height: HUDLayout.edgePickerHeight)
                        .background(
                            Capsule()
                                .fill(selectedLimit == choice.1 ? Palette.ample : Palette.ringTrack)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copilot \(choice.0) plan, \(choice.1) monthly premium requests")
                .accessibilityValue(selectedLimit == choice.1 ? "Selected" : "Not selected")
            }
        }
    }
}

private struct EdgePicker: View {
    let edge: NotchEdge
    let onSelect: (NotchEdge) -> Void

    var body: some View {
        HStack(spacing: Design.px(12)) {
            ForEach(NotchEdge.allCases, id: \.rawValue) { candidate in
                Button(action: { onSelect(candidate) }) {
                    HStack(spacing: Design.px(7)) {
                        Image(systemName: icon(for: candidate))
                        Text(candidate.rawValue.capitalized)
                    }
                    .font(Typography.cardBody)
                    .foregroundStyle(edge == candidate ? Color.white : Palette.textSecondary)
                    .padding(.horizontal, Design.px(13))
                    .frame(height: HUDLayout.edgePickerHeight)
                    .background(
                        Capsule()
                            .fill(edge == candidate ? Palette.ample : Palette.ringTrack)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Move HUD to \(candidate.rawValue) edge")
                .accessibilityValue(edge == candidate ? "Selected" : "Not selected")
            }
        }
    }

    private func icon(for edge: NotchEdge) -> String {
        switch edge {
        case .right: return "rectangle.righthalf.inset.filled"
        case .left: return "rectangle.lefthalf.inset.filled"
        case .top: return "rectangle.tophalf.inset.filled"
        case .bottom: return "rectangle.bottomhalf.inset.filled"
        }
    }
}

private struct SettingsProviderRow: View {
    let id: String
    let name: String
    let isOn: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onToggle: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void

    var body: some View {
        HStack(spacing: HUDLayout.headerGap) {
            if let glyph = ProviderGlyph.from(providerId: id) {
                ProviderGlyphView(glyph: glyph)
                    .foregroundStyle(Palette.textPrimary)
                    .frame(width: HUDLayout.glyphSize, height: HUDLayout.glyphSize)
            }
            Text(name)
                .font(Typography.cardBody)
                .foregroundStyle(Palette.textPrimary)
            Spacer(minLength: 0)
            moveButton(systemName: "arrow.up", enabled: canMoveUp, action: onMoveUp)
            moveButton(systemName: "arrow.down", enabled: canMoveDown, action: onMoveDown)
            Button(action: onToggle) {
                BespokeSwitch(isOn: isOn)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show \(name)")
            .accessibilityValue(isOn ? "On" : "Off")
            .accessibilityHint("Shows or hides this provider on the rail")
        }
        .frame(height: HUDLayout.settingsRowHeight)
        .focusable()
    }

    private func moveButton(systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(Typography.cardBody)
                .foregroundStyle(enabled ? Palette.textPrimary : Palette.textSecondary.opacity(0.35))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(systemName == "arrow.up" ? "Move \(name) earlier" : "Move \(name) later")
    }
}

private struct RoutingToolRow: View {
    let tool: RoutingToolState
    let onToggleAvailability: () -> Void

    var body: some View {
        HStack(spacing: HUDLayout.headerGap) {
            ProviderGlyphView(glyph: ProviderGlyph.from(providerId: tool.id) ?? .third)
                .foregroundStyle(Palette.textPrimary)
                .frame(width: HUDLayout.glyphSize, height: HUDLayout.glyphSize)
            Text(tool.label)
                .font(Typography.cardBody)
                .foregroundStyle(Palette.textPrimary)
            Spacer(minLength: 0)
            statusButton(
                title: tool.available ? "Available" : "Unavailable",
                isOn: tool.available,
                action: onToggleAvailability
            )
        }
        .frame(height: HUDLayout.settingsRowHeight)
        .focusable()
    }

    private func statusButton(title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Design.px(10)) {
                Text(title)
                    .font(Typography.cardBody)
                    .foregroundStyle(isOn ? Palette.textPrimary : Palette.textSecondary)
                BespokeSwitch(isOn: isOn)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(tool.label) \(title)")
    }
}

private struct BespokeSwitch: View {
    let isOn: Bool

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? Palette.ample : Palette.ringTrack)
            Circle()
                .fill(Color.white)
                .padding(2)
        }
        .frame(width: Design.px(52), height: Design.px(30))
        .accessibilityHidden(true)
    }
}
