import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: UsageStore
    let edge: NotchEdge
    let onEdgeChange: (NotchEdge) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Screen edge")
                .font(Typography.cardTitle)
                .foregroundStyle(Palette.textPrimary)

            EdgePicker(edge: edge, onSelect: onEdgeChange)
                .padding(.top, HUDLayout.headerToBlock)

            Text("Visible providers")
                .font(Typography.cardTitle)
                .foregroundStyle(Palette.textPrimary)
                .padding(.top, 2 * HUDLayout.blockSpacing)

            ForEach(Array(store.providerCatalog.enumerated()), id: \.element.id) { index, provider in
                SettingsProviderRow(
                    id: provider.id,
                    name: provider.label,
                    isOn: store.enabledProviderIds.contains(provider.id),
                    canMoveUp: index > 0,
                    canMoveDown: index < store.providerCatalog.count - 1,
                    onToggle: { store.toggle(providerId: provider.id) },
                    onMoveUp: { store.moveProvider(provider.id, by: -1) },
                    onMoveDown: { store.moveProvider(provider.id, by: 1) }
                )
                .padding(.top, index == 0 ? HUDLayout.headerToBlock : HUDLayout.blockSpacing)
            }

            if !store.routingToolStates.isEmpty {
                Text("Agent routing")
                    .font(Typography.cardTitle)
                    .foregroundStyle(Palette.textPrimary)
                    .padding(.top, 2 * HUDLayout.blockSpacing)

                ForEach(store.routingToolStates) { tool in
                    RoutingToolRow(
                        tool: tool,
                        onToggleEnabled: { store.toggleRoutingTool(tool.id) },
                        onToggleAvailability: { store.toggleRoutingToolAvailability(tool.id) }
                    )
                    .padding(.top, HUDLayout.headerToBlock)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(Palette.textPrimary)
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
    let onToggleEnabled: () -> Void
    let onToggleAvailability: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Design.px(10)) {
            HStack(spacing: HUDLayout.headerGap) {
                ProviderGlyphView(glyph: ProviderGlyph.from(providerId: tool.id) ?? .third)
                    .foregroundStyle(Palette.textPrimary)
                    .frame(width: HUDLayout.glyphSize, height: HUDLayout.glyphSize)
                Text(tool.label)
                    .font(Typography.cardBody)
                    .foregroundStyle(Palette.textPrimary)
                Spacer(minLength: 0)
                statusButton(
                    title: tool.enabled ? "Enabled" : "Disabled",
                    isOn: tool.enabled,
                    action: onToggleEnabled
                )
            }
            HStack {
                Spacer(minLength: HUDLayout.glyphSize + HUDLayout.headerGap)
                statusButton(
                    title: tool.available ? "Available" : "Unavailable",
                    isOn: tool.available,
                    action: onToggleAvailability
                )
            }
        }
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
