/// Where a recognized horizontal toolbar swipe goes.
enum MobileToolbarSwipeDestination: CaseIterable, Equatable, Sendable {
    /// The next or previous card of the presented split, clamped at the ends.
    case adjacentCard
    /// The next or previous Space. Reachable only from
    /// `MobileToolbarSwipeMode.contextual`, which nothing ships with today.
    case adjacentSpace
    /// Recognized and deliberately ignored. The recognizer stays installed —
    /// the same finger travel means something the moment a split is open, and a
    /// gesture that appears only in some states is harder to learn than one that
    /// is simply quiet in others.
    case none
}
