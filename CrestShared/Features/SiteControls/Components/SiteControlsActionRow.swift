import SwiftUI

/// The actions on top of Site Controls as a row of tiles that share its
/// width. A tile picked up lifts out of the row and follows the pointer; held
/// over the row, the others open a gap where it would land, and held away
/// from it, they close up behind it, since letting it go there takes it off.
/// An action dragged up from the editor's list opens a gap the same way,
/// letting the last go when there are four. While the editor shows the row,
/// each tile wears its slot's number, and the slots still empty wait at the
/// end for an action.
struct SiteControlsActionRow: View {
    // MARK: - Types

    /// One place in the row: a tile, or the gap a drag holds open.
    private enum Place: Identifiable {
        case tile(SiteControlsModel.ActionItem, slot: Int)
        case gap
        case empty(slot: Int)

        var id: String {
            switch self {
            case .tile(let item, _): item.id
            case .gap: "gap"
            case .empty(let slot): "empty-\(slot)"
            }
        }
    }

    // MARK: - Variables

    let model: SiteControlsModel
    /// Whether the editor shows the row, which numbers its slots and chooses
    /// one rather than running an action.
    var isEditing = false

    @Environment(\.siteControlsMetrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let places = places
        HStack(spacing: metrics.tileSpacing) {
            ForEach(places) { place in
                switch place {
                case .tile(let item, let slot): tile(item, slot: slot)
                case .gap: gap
                case .empty(let slot): empty(slot: slot)
                }
            }
        }
        .frame(height: metrics.actionTileHeight)
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: SiteControlsModel.space) }) { frame in
            // Only the row on screen says where drags land: the root's, or
            // the editor's while its page shows. One sliding away keeps quiet.
            guard isEditing == (model.shownPage != nil) else { return }
            model.actionRowFrame = frame
        }
        .siteControlsActionDragSource(model, isEnabled: dragsTiles) { start, location in
            pickUp(at: start, pointer: location)
        }
        .animation(CrestMotion.dragSource.unlessReducingMotion(reduceMotion), value: places.map(\.id))
    }

    /// Whether a tile lifts when dragged. A finger's hold opens a tile's
    /// menu on the root, so there a tile moves only in the editor.
    private var dragsTiles: Bool {
        #if os(iOS)
            isEditing
        #else
            true
        #endif
    }

    /// Whether a tile offers its menu. In the editor a finger's hold lifts
    /// the tile instead, and the editor offers all the menu does.
    private var offersTileMenu: Bool {
        #if os(iOS)
            !isEditing
        #else
            true
        #endif
    }

    // MARK: - Actions - Places

    /// The row as it shows now: the actions on top, with a drag lifting its
    /// own tile out, holding a gap where it would land over the row or where
    /// it would go back to away from it, and in the editor the empty slots
    /// after them.
    private var places: [Place] {
        var places = model.topActions.enumerated().map { Place.tile($1, slot: $0) }
        if let drag = model.drag {
            let lifted = places.firstIndex { $0.id == drag.action.name }
            if let index = model.dropIndex {
                if let lifted { places.remove(at: lifted) }
                places.insert(.gap, at: min(index, places.count))
                if places.count > SiteControlTopActions.maximumCount { places.removeLast() }
            } else if drag.isFromRow, let lifted {
                places.remove(at: lifted)
                if !model.dragRemoves { places.insert(.gap, at: lifted) }
            }
        }
        if isEditing {
            places += (places.count..<SiteControlTopActions.maximumCount).map { Place.empty(slot: $0) }
        }
        return places
    }

    /// The tile under `start`, picked up with the pointer now at `pointer`,
    /// keeping where the pointer holds it; nil over an empty slot.
    private func pickUp(at start: CGPoint, pointer: CGPoint) -> SiteControlsModel.ActionDrag? {
        let frame = model.actionRowFrame
        let actions = model.topActions
        let count = isEditing ? SiteControlTopActions.maximumCount : actions.count
        guard frame.width > 0, count > 0 else { return nil }
        let pitch = (frame.width + metrics.tileSpacing) / CGFloat(count)
        let slot = Int((start.x - frame.minX) / pitch)
        guard actions.indices.contains(slot) else { return nil }
        let center = CGPoint(x: frame.minX + pitch * CGFloat(slot) + (pitch - metrics.tileSpacing) / 2, y: frame.midY)
        return SiteControlsModel.ActionDrag(
            action: actions[slot].action, isFromRow: true,
            size: CGSize(width: pitch - metrics.tileSpacing, height: metrics.actionTileHeight),
            grab: CGSize(width: start.x - center.x, height: start.y - center.y), location: pointer)
    }

    // MARK: - Actions - Drawing

    private func tile(_ item: SiteControlsModel.ActionItem, slot: Int) -> some View {
        SiteControlsActionTile(
            item: item, height: metrics.actionTileHeight, slotNumber: isEditing ? slot + 1 : nil,
            isSelected: isEditing && model.selectedSlot == slot
        ) {
            guard !model.suppressesActivation, model.drag == nil else { return }
            if isEditing { model.selectedSlot = slot } else { model.run(item.action) }
        }
        .modifier(SiteControlsTileMenuModifier(model: model, slot: slot, isEnabled: offersTileMenu))
        .accessibilityLabel(
            isEditing ? Text("Slot \(slot + 1), \(String(localized: item.title))") : Text(item.title)
        )
        .accessibilityValue(isEditing && model.selectedSlot == slot ? Text("Chosen") : Text(verbatim: ""))
        .accessibilityHint(isEditing ? Text("Choose an action below to put in this slot") : Text(verbatim: ""))
        .accessibilityAction(named: "Move Left") { move(item.action, from: slot, by: -1) }
        .accessibilityAction(named: "Move Right") { move(item.action, from: slot, by: 1) }
        .accessibilityAction(named: "Remove from Actions") { model.remove(item.action) }
        .accessibilityIdentifier(
            isEditing ? "site-controls-slot-\(slot + 1)" : "site-control-action-\(item.action.name)")
    }

    private var gap: some View {
        RoundedRectangle(cornerRadius: CrestRadius.compact)
            .fill(CrestColor.chromeSurface.opacity(0.5))
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }

    private func empty(slot: Int) -> some View {
        let isSelected = model.selectedSlot == slot
        return Button {
            model.selectedSlot = slot
        } label: {
            Image(systemName: "plus")
                .font(.system(size: metrics.actionGlyphSize * 0.8, weight: .medium))
                .foregroundStyle(isSelected ? CrestBrandTheme.accentText : .secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background {
            RoundedRectangle(cornerRadius: CrestRadius.compact)
                .strokeBorder(
                    isSelected ? CrestBrandTheme.accent : Color.secondary.opacity(0.4),
                    style: StrokeStyle(lineWidth: isSelected ? 2 : 1, dash: isSelected ? [] : [4, 3]))
        }
        .accessibilityLabel(Text("Empty slot \(slot + 1)"))
        .accessibilityValue(isSelected ? Text("Chosen") : Text(verbatim: ""))
        .accessibilityHint("Choose an action below to put in this slot")
        .accessibilityIdentifier("site-controls-slot-\(slot + 1)")
    }

    /// Moves a tile one slot along, as its context menu's Move Left and Move
    /// Right do.
    private func move(_ action: SiteControlAction, from slot: Int, by offset: Int) {
        let target = slot + offset
        guard model.topActions.indices.contains(target) else { return }
        model.move(action, to: target)
    }
}

/// A tile's menu, where the row offers one.
private struct SiteControlsTileMenuModifier: ViewModifier {
    let model: SiteControlsModel
    let slot: Int
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content.contextMenu { SiteControlsTileMenu(model: model, slot: slot) }
        } else {
            content
        }
    }
}
