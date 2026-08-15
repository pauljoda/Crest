import CoreGraphics

/// Where a tab dragged over the content area would land among the cards already
/// on show. Pure geometry, so a drop can be exercised without a live drag.
///
/// The columns view lays cards out in reading order along one axis, so the rule
/// is the horizontal twin of `BrowserSidebarReorderPolicy.insertionIndex`: the
/// pointer has passed a card once it is beyond that card's midpoint, and the
/// index is how many cards it has passed.
///
/// Only presented cards are measured. The drop placeholder registers no frame of
/// its own, and the cards it displaces provably keep the same answer: inserting a
/// placeholder at `index` moves every earlier card's midpoint left and every
/// later card's midpoint right, which is the direction that reinforces the index
/// the pointer already resolved. That is what lets the placeholder appear without
/// the layout it causes changing the slot it appears in.
enum BrowserSplitDropPolicy {
    /// The slot the dragged tab would take among `orderedCardFrames`, in
    /// `0...orderedCardFrames.count`.
    ///
    /// A lone card is not a special case: the pointer resolves to `0` on its
    /// leading half and `1` on its trailing half, which is exactly how a split
    /// gets created out of a window presenting one tab.
    static func insertionIndex(
        at point: CGPoint,
        orderedCardFrames: [CGRect]
    ) -> Int {
        var index = 0
        for frame in orderedCardFrames {
            guard point.x > frame.midX else { break }
            index += 1
        }
        return index
    }

    /// Reading order for measured cards.
    ///
    /// Sorting by leading edge rather than trusting a dictionary's iteration is
    /// what keeps the index tied to what is on screen. It matches the ordering
    /// `BrowserSidebarReorderPolicy` already uses for the pinned grid, including
    /// its indifference to layout direction.
    static func ordered(_ frames: [CGRect]) -> [CGRect] {
        frames.filter { !$0.isEmpty }.sorted { $0.minX < $1.minX }
    }
}
