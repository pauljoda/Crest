import Foundation

/// The fixed limits a split group obeys everywhere it is read or mutated.
///
/// A group is never its own collection: it is the maximal contiguous run of
/// tabs in a Space sharing a `splitGroupID`, in session-array order. These
/// constants are what every query, normalizer, mutation, and presentation
/// surface agrees on, so a run that one layer considers renderable is
/// renderable in all of them.
///
/// Reserved seam — extension side panels. A later release adds panel cards
/// alongside web-view cards. Those panels are device-local by design (an
/// extension's side panel is not a person's browsing state and must never
/// sync), so they will live in a `BrowserLocalSplitPanelStore` keyed by
/// `SplitGroupID` rather than as members of the run. Its repair pass drops
/// every entry whose key is absent from `BrowserSpace.liveSplitGroupIDs`,
/// which is what makes "break up a split on one device" converge cleanly on
/// every other device without any cross-device panel record. Design note
/// only: nothing below builds it.
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
