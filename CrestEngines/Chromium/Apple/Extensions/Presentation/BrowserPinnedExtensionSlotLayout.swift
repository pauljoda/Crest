import SwiftUI

/// Lays a Space's pinned extension tiles out in one row by slot, as the pinned
/// tab grid lays out its tiles: while a tile is carried, the others close up
/// around a gap where it would land. The carried tile keeps its own slot out
/// of sight rather than leaving the view tree, which would end its drag.
struct BrowserPinnedExtensionSlotLayout: Layout {
    // MARK: - Types

    enum Slot: Equatable {
        case tile(String)
        case gap
    }

    // MARK: - Static Variables

    static let tileSize: CGFloat = 24
    static let spacing: CGFloat = 6
    /// How far one slot is from the next.
    static let pitch = tileSize + spacing

    // MARK: - Variables

    /// The tiles, in the order their views come.
    let ids: [String]
    /// The carried tile, which takes no slot of its own.
    var liftedID: String?
    /// The slot the gap holds open for the carried tile.
    var gapIndex = 0

    /// The row's slots: every tile but the carried one, and the gap it would
    /// land in.
    var slots: [Slot] {
        guard let liftedID, ids.contains(liftedID) else { return ids.map(Slot.tile) }
        var slots = ids.filter { $0 != liftedID }.map(Slot.tile)
        slots.insert(.gap, at: min(max(gapIndex, 0), slots.count))
        return slots
    }

    // MARK: - Actions - Geometry

    /// The frame of the slot at `index` in a row whose first slot starts at
    /// `origin`.
    static func frame(ofSlot index: Int, from origin: CGPoint) -> CGRect {
        CGRect(x: origin.x + CGFloat(index) * pitch, y: origin.y, width: tileSize, height: tileSize)
    }

    /// The slot a tile whose leading edge is at `x` lands in, in a row of
    /// `count` slots whose first starts at `originX`.
    static func slot(at x: CGFloat, originX: CGFloat, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(Int(((x - originX) / pitch).rounded()), 0), count - 1)
    }

    // MARK: - Actions - Layout

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let count = CGFloat(ids.count)
        return CGSize(width: max(0, count * Self.pitch - Self.spacing), height: Self.tileSize)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let slots = slots
        for (index, subview) in subviews.enumerated() where ids.indices.contains(index) {
            let slot = slots.firstIndex(of: .tile(ids[index])) ?? index
            subview.place(
                at: Self.frame(ofSlot: slot, from: bounds.origin).origin, anchor: .topLeading,
                proposal: ProposedViewSize(width: Self.tileSize, height: Self.tileSize))
        }
    }
}
