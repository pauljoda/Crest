import CoreGraphics

/// The temporary pinned slots, shared by rendering and drop hit testing.
/// A lifted tile stays alive in the view tree but occupies no slot of its own.
struct BrowserPinnedTabReorderLayout: Equatable {
    enum Slot: Equatable {
        case tab(BrowserSidebarReorderItemID)
        case gap
    }

    static let cellHeight: CGFloat = 47
    static let spacing = CrestSpacing.small

    let ids: [BrowserSidebarReorderItemID]
    var liftedID: BrowserSidebarReorderItemID?
    var insertionIndex: Int?

    var slots: [Slot] {
        var result = ids.filter { $0 != liftedID }.map(Slot.tab)
        if let insertionIndex {
            result.insert(.gap, at: min(max(0, insertionIndex), result.count))
        }
        return result
    }

    var columns: Int { PinnedTabGridLayout.columnCount(for: slots.count) }

    var height: CGFloat {
        guard !slots.isEmpty else { return 0 }
        let rows = (slots.count + columns - 1) / columns
        return CGFloat(rows) * Self.cellHeight + CGFloat(rows - 1) * Self.spacing
    }

    func frame(for slot: Slot, in bounds: CGRect) -> CGRect? {
        guard let index = slots.firstIndex(of: slot) else { return nil }
        let width = max(0, (bounds.width - CGFloat(columns - 1) * Self.spacing) / CGFloat(columns))
        return CGRect(
            x: bounds.minX + CGFloat(index % columns) * (width + Self.spacing),
            y: bounds.minY + CGFloat(index / columns) * (Self.cellHeight + Self.spacing),
            width: width, height: Self.cellHeight)
    }
}
