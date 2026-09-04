import Foundation

/// The fixed limits a split group obeys everywhere it is read or mutated.
///
/// A group is never its own collection: it is the maximal contiguous run of
/// tabs in a Space sharing a `splitGroupID`, in session-array order. These
/// constants are what every query, normalizer, mutation, and presentation
/// surface agrees on, so a run that one layer considers renderable is
/// renderable in all of them.
///
/// Extension side panels occupy a separate row slot keyed by native window
/// and Space. They are not group members, do not affect column fractions,
/// and never enter synced browsing state.
enum BrowserSplitGroupPolicy {
    /// The largest number of tabs one split group renders as columns. Arc and
    /// Zen both stop at four, and four 240pt-minimum cards is already the
    /// practical limit of a laptop-width window.
    static let maximumMembers = 4

    /// The smallest run that presents as a split rather than as plain tabs.
    /// A shorter run keeps its membership in storage — see
    /// `BrowserSplitGroupNormalizer.normalized(_:)` — and simply renders as an
    /// ordinary tab until its siblings arrive.
    static let minimumRenderableMembers = 2

    /// Whether a tab in this placement may carry a group at all.
    ///
    /// Pinned tabs are a fixed grid of site shortcuts rather than an ordered
    /// browsing run, so they never take part in a split.
    static func allowsMembership(placement: TabPlacement) -> Bool {
        placement != .pinned
    }
}
