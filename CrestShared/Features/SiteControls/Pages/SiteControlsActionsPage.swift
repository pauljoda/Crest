import SwiftUI

/// Every action outside the row on top, in its group, each run from its row;
/// or, while editing, every action the device offers under that row. The
/// person drags an action up into the row and a tile out of it, or chooses a
/// slot and then an action, which works from the keyboard and with VoiceOver
/// too; choosing one already in the row trades the two.
struct SiteControlsActionsPage: View {
    let model: SiteControlsModel

    @Environment(\.siteControlsMetrics) private var metrics

    var body: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.medium) {
            ForEach(SiteControlActionGroup.all, id: \.self) { group in
                let actions = actions(in: group)
                if !actions.isEmpty {
                    SiteControlsPageSection(title: group.title) {
                        ForEach(actions) { action in
                            if model.isEditingActions { choice(action) } else { row(action) }
                        }
                    }
                }
            }
            if model.isEditingActions {
                SiteControlsPageSection(footer: Text("Saved on this device.")) {
                    SiteControlsRow(
                        title: Text("Reset to Default"), symbol: "arrow.uturn.backward",
                        titleTint: CrestBrandTheme.accentText, action: { model.resetActions() }
                    ) {
                        EmptyView()
                    }
                    .accessibilityIdentifier("site-controls-reset-actions")
                }
            }
        }
    }

    /// The actions a group lists: while editing every one the device offers,
    /// otherwise those not on top, leaving out one that shows only
    /// while it can run and cannot now.
    private func actions(in group: SiteControlActionGroup) -> [SiteControlAction] {
        let source = model.isEditingActions ? model.offeredActions : model.moreActions
        return source.filter { action in
            action.group == group
                && (model.isEditingActions || !action.showsOnlyWhenAvailable
                    || model.platform.state(of: action).isAvailable)
        }
    }

    // MARK: - Running

    private func row(_ action: SiteControlAction) -> some View {
        let item = model.item(action)
        return SiteControlsRow(title: Text(item.title), symbol: item.symbol) {
            model.run(action)
        } trailing: {
            if let shortcut = item.shortcut {
                SiteControlsRowValue(value: shortcut.displayString)
            }
        }
        .disabled(!item.state.isAvailable)
        .accessibilityIdentifier(
            action == .addToHomeScreen
                ? BrowserMobileAccessibilityID.pageActionsAddToHomeScreen : "site-control-more-\(action.name)")
    }

    // MARK: - Editing

    /// An action as the editor lists it: its place in the row on top, or a plus,
    /// and it goes into the chosen slot when chosen.
    private func choice(_ action: SiteControlAction) -> some View {
        let item = model.item(action)
        let rank = model.core.state.siteControlTopActions.actions.firstIndex(of: action).map { $0 + 1 }
        return SiteControlsRow(title: Text(item.title), symbol: item.symbol) {
            guard !model.suppressesActivation, model.drag == nil else { return }
            model.placeInSelectedSlot(action)
        } trailing: {
            SiteControlsRank(rank: rank)
        }
        .siteControlsActionDragSource(model) { _, location in pickUp(action, pointer: location) }
        .accessibilityLabel(Text(item.title))
        .accessibilityValue(rank.map { Text("In slot \($0)") } ?? Text(verbatim: ""))
        .accessibilityHint(Text("Puts it in slot \(model.selectedSlot + 1)"))
        .accessibilityIdentifier("site-controls-choose-\(action.name)")
    }

    /// `action` picked up from the list, drawn as a tile the size of one in a
    /// full row, centered under the pointer.
    private func pickUp(_ action: SiteControlAction, pointer: CGPoint) -> SiteControlsModel.ActionDrag {
        let slots = CGFloat(SiteControlTopActions.maximumCount)
        let width = (model.actionRowFrame.width - metrics.tileSpacing * (slots - 1)) / slots
        return SiteControlsModel.ActionDrag(
            action: action, isFromRow: false, size: CGSize(width: max(width, 0), height: metrics.actionTileHeight),
            grab: .zero, location: pointer)
    }
}

/// An action's place in the row on top, as a numbered Crest-blue disc, or an
/// outlined plus for one that is not there.
private struct SiteControlsRank: View {
    let rank: Int?

    var body: some View {
        Group {
            if let rank {
                Text(verbatim: "\(rank)")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 18, height: 18)
                    .background(CrestBrandTheme.accent, in: .circle)
            } else {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .overlay { Circle().strokeBorder(.secondary.opacity(0.5), lineWidth: 1.5) }
            }
        }
        .accessibilityHidden(true)
    }
}
