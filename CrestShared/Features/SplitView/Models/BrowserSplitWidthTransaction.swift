import CoreGraphics

/// Keeps pointer-frequency column resizing in view-owned memory.
///
/// The same bargain `BrowserSidebarWidthTransaction` makes: a drag updates live
/// fractions every frame, and the durable per-window record advances once, when
/// the interaction commits. Without it a divider drag would make window-state
/// persistence an animation-rate source of SwiftUI invalidations.
struct BrowserSplitWidthTransaction: Equatable {
    private(set) var fractions: [Double]
    private(set) var persistedFractions: [Double]

    /// The fractions the in-flight drag measures from, captured once when the
    /// drag first reports and held until it ends.
    ///
    /// A drag reports its total travel rather than each frame's step, so
    /// applying `delta` to the live fractions would compound it. Holding the
    /// baseline is also what makes the drag idempotent: the same total travel
    /// applied on any number of layout passes answers the same fractions, so a
    /// pointer that has stopped moving leaves the layout exactly where it is.
    private var dragBaseline: [Double]?

    /// The smallest fraction change worth a durable write: below a thousandth
    /// of the container, which is well under a point on any real window.
    private static let minimumMeaningfulChange = 0.0005

    init(persistedFractions: [Double]) {
        let fractions = BrowserSplitColumnLayout.normalizedFractions(persistedFractions)
        self.fractions = fractions
        self.persistedFractions = fractions
    }

    /// Adopts a new set of fractions as both the live and the committed layout.
    ///
    /// This is how a view follows the presented group changing, or a member
    /// count changing under a group: the incoming fractions are already the
    /// truth, so there is nothing to commit and no drag left in flight.
    mutating func begin(fractions: [Double]) {
        let normalized = BrowserSplitColumnLayout.normalizedFractions(fractions)
        self.fractions = normalized
        persistedFractions = normalized
        dragBaseline = nil
    }

    /// Moves one divider by the drag's total travel.
    ///
    /// The first call after `begin` or `commit` snapshots the fractions the drag
    /// started from, so every later frame of the same drag resolves against that
    /// snapshot. A single-step adjustment — an accessibility increment, say —
    /// commits after each step and therefore always measures from the layout on
    /// screen.
    mutating func resize(dividerIndex: Int, delta: CGFloat, containerWidth: CGFloat) {
        let baseline = dragBaseline ?? fractions
        dragBaseline = baseline
        fractions = BrowserSplitColumnLayout.fractionsAfterResize(
            fractions: baseline,
            dividerIndex: dividerIndex,
            delta: delta,
            containerWidth: containerWidth
        )
    }

    /// Ends the interaction, answering the fractions to persist and `nil` when
    /// the drag left the layout where it found it.
    mutating func commit() -> [Double]? {
        dragBaseline = nil
        guard !Self.matches(fractions, persistedFractions) else { return nil }
        persistedFractions = fractions
        return fractions
    }

    private static func matches(_ fractions: [Double], _ other: [Double]) -> Bool {
        guard fractions.count == other.count else { return false }
        return zip(fractions, other).allSatisfy { pair in
            abs(pair.0 - pair.1) < minimumMeaningfulChange
        }
    }
}
