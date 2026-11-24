import SwiftUI

/// The actions the person keeps on top, under their label with Edit
/// beside it. A tile that turns something on says so in place, in Crest
/// blue. A tile's context menu replaces or moves it, or opens the editor.
struct SiteControlsActionTiles: View {
    let model: SiteControlsModel

    @Environment(\.siteControlsMetrics) private var metrics

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SiteControlsSectionHeader(title: "Actions") {
                Button("Edit") { model.editActions() }
                    .buttonStyle(SiteControlsTextButtonStyle())
                    .accessibilityLabel("Edit Top Actions")
                    .accessibilityIdentifier("site-controls-edit-actions")
            }
            SiteControlsActionRow(model: model)
        }
    }
}

/// One action as a tile: its symbol over its short title, with its full
/// title and keys as help. A tile whose state is on wears Crest blue.
struct SiteControlsActionTile: View {
    let item: SiteControlsModel.ActionItem
    let height: CGFloat
    var slotNumber: Int?
    var isSelected = false
    let action: () -> Void

    @Environment(\.siteControlsMetrics) private var metrics

    var body: some View {
        Button(action: action) {
            VStack(spacing: CrestSpacing.extraSmall) {
                Image(systemName: item.symbol)
                    .font(.system(size: metrics.actionGlyphSize, weight: .medium))
                    .frame(height: metrics.actionGlyphSize + 2)
                Text(item.shortTitle)
                    .font(metrics.tileFont)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .padding(.horizontal, CrestSpacing.extraSmall)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .overlay(alignment: .topLeading) {
                if let slotNumber {
                    Text(verbatim: "\(slotNumber)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(isSelected ? CrestBrandTheme.accentText : .secondary)
                        .padding(.leading, 6)
                        .padding(.top, 4)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(
            CrestChromeButtonStyle(
                controlSize: nil, cornerRadius: CrestRadius.compact, showsRestingFill: true,
                isSelected: item.isOn || isSelected, tint: item.isOn || isSelected ? CrestBrandTheme.accentText : nil)
        )
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: CrestRadius.compact)
                    .strokeBorder(CrestBrandTheme.accent, lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
        .disabled(!item.state.isAvailable && slotNumber == nil)
        .help(item.help)
        .accessibilityLabel(Text(item.title))
        .accessibilityValue(item.isOn ? Text("On") : Text(verbatim: ""))
        .accessibilityAddTraits(item.isOn ? .isSelected : [])
    }
}

/// What a tile's context menu offers: another action in its place, a move
/// to either side, leaving the row, the editor, and the default four.
struct SiteControlsTileMenu: View {
    let model: SiteControlsModel
    let slot: Int

    var body: some View {
        Group {
            Menu {
                ForEach(SiteControlActionGroup.all, id: \.self) { group in
                    let actions = model.offeredActions.filter { $0.group == group }
                    if !actions.isEmpty {
                        Section {
                            ForEach(actions) { action in
                                Button {
                                    model.place(action, in: slot)
                                } label: {
                                    Label {
                                        Text(action.title)
                                    } icon: {
                                        Image(systemName: action.symbol)
                                    }
                                }
                            }
                        } header: {
                            Text(group.title)
                        }
                    }
                }
                .crestMenuActionLabelStyle()
            } label: {
                Label("Replace With", systemImage: "arrow.left.arrow.right")
            }
            Button("Move Left", systemImage: "arrow.left") { move(by: -1) }
                .disabled(slot == 0)
            Button("Move Right", systemImage: "arrow.right") { move(by: 1) }
                .disabled(slot >= model.topActions.count - 1)
            Button("Remove from Actions", systemImage: "minus.circle") {
                guard model.topActions.indices.contains(slot) else { return }
                model.remove(model.topActions[slot].action)
            }
            .disabled(model.topActions.count < 2)
            Divider()
            Button("Edit Actions…", systemImage: "pencil") { model.editActions(selecting: slot) }
            Button("Reset to Default", systemImage: "arrow.uturn.backward") { model.resetActions() }
        }
        .crestMenuActionLabelStyle()
    }

    /// Moves the tile one slot along, its neighbor taking its place.
    private func move(by offset: Int) {
        let actions = model.core.state.siteControlTopActions.actions
        let target = slot + offset
        guard actions.indices.contains(target) else { return }
        model.move(actions[slot], to: target)
    }
}
