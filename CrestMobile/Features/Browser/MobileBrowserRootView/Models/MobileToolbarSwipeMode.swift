/// What the horizontal toolbar swipe is for on this build.
enum MobileToolbarSwipeMode: CaseIterable, Equatable, Sendable {
    /// Shipping in 0.4. The swipe belongs to Split View and nothing else: it
    /// pages cards inside a group and does nothing outside one.
    ///
    /// A gesture that means two different things depending on invisible state is
    /// a gesture nobody can trust, and Spaces have a home the swipe never had —
    /// the tab viewer's Space switcher, which shows what it is switching to.
    case cardsOnly

    /// The documented future slot, not wired to any setting. Restores the old
    /// Space swipe *outside* a group while cards keep it inside one. Left here
    /// because the choice is a product decision that may be revisited, and the
    /// routing that would carry it already exists.
    case contextual
}
