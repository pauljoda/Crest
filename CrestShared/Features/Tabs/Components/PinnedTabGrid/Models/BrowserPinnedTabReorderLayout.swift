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
    var liftedIDs: Set<BrowserSidebarReorderItemID> = []
    var insertionIndex: Int?
    var availableWidth: CGFloat = BrowserChromeLayout.sidebarIdealWidth
    var preferredColumns = 0
    var tabScale = 1.0
    var tileHeight: CGFloat = Self.cellHeight
    var tileSpacing: CGFloat = Self.spacing
    var minimumTileWidth: CGFloat = BrowserSidebarDensityPolicy.pinMinimumWidth(scale: 1)

    var slots: [Slot] {
        var result = ids.filter { $0 != liftedID && !liftedIDs.contains($0) }.map(Slot.tab)
        if let insertionIndex {
            result.insert(.gap, at: min(max(0, insertionIndex), result.count))
        }
        return result
    }

    var columns: Int {
        let automaticCapacity = Int(
            (Double(PinnedTabGridLayout.maximumColumns) / BrowserSidebarDensityPolicy.scale(tabScale)).rounded())
        let requested = preferredColumns == 0 ? min(max(automaticCapacity, 1), 6) : min(max(preferredColumns, 1), 6)
        let width =
            availableWidth.isFinite ? min(max(0, availableWidth), 10_000) : BrowserChromeLayout.sidebarIdealWidth
        let fitting = max(1, Int((width + tileSpacing) / (minimumTileWidth + tileSpacing)))
        return PinnedTabGridLayout.columnCount(for: slots.count, maximumColumns: min(requested, fitting))
    }

    var height: CGFloat {
        guard !slots.isEmpty else { return 0 }
        let rows = (slots.count + columns - 1) / columns
        return CGFloat(rows) * tileHeight + CGFloat(rows - 1) * tileSpacing
    }

    func frame(for slot: Slot, in bounds: CGRect) -> CGRect? {
        guard let index = slots.firstIndex(of: slot) else { return nil }
        let width = max(0, (bounds.width - CGFloat(columns - 1) * tileSpacing) / CGFloat(columns))
        return CGRect(
            x: bounds.minX + CGFloat(index % columns) * (width + tileSpacing),
            y: bounds.minY + CGFloat(index / columns) * (tileHeight + tileSpacing),
            width: width, height: tileHeight)
    }

    @MainActor
    func applyingPreferences(width: CGFloat) -> Self {
        var value = self
        value.availableWidth = width.isFinite ? max(0, width) : BrowserChromeLayout.sidebarIdealWidth
        value.preferredColumns = Int(
            min(
                max(
                    BrowserSidebarDensityPreference.number(BrowserSidebarDensityPreference.pinColumnsKey, default: 0), 0
                ), 6))
        let scale = BrowserSidebarDensityPreference.number(BrowserSidebarDensityPreference.scaleKey, default: 1)
        value.tabScale = scale
        value.tileHeight = BrowserSidebarDensityPolicy.pinHeight(scale: scale)
        value.tileSpacing = BrowserSidebarDensityPolicy.pinSpacing(scale: scale)
        value.minimumTileWidth = BrowserSidebarDensityPolicy.pinMinimumWidth(scale: scale)
        return value
    }
}
