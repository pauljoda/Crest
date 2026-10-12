/// What the horizontal toolbar swipe is for on this build.
///
/// One gesture, one owner. `BrowserSpaceSwipeDirection` still decides whether a
/// drag counts as a deliberate horizontal swipe and which way it points; the
/// mode decides what that swipe is *for*, which as of 0.4 is Split View.
///
/// The recognizer is unconditional on purpose. Making it appear only inside a
/// group would mean the toolbar behaved differently from one tab to the next
/// with nothing on screen to explain why; answering `.ignored` keeps the
/// gesture in one place and simply quiet where there is no second card.
struct MobileToolbarSwipeMode: Equatable, Sendable {
    // MARK: - Static Variables

    /// Shipping in 0.4. The swipe belongs to Split View and nothing else: it
    /// pages cards inside a group and does nothing outside one.
    ///
    /// A gesture that means two different things depending on invisible state is
    /// a gesture nobody can trust, and Spaces have a home the swipe never had —
    /// the tab viewer's Space switcher, which shows what it is switching to.
    static let cardsOnly = MobileToolbarSwipeMode(name: "cardsOnly", outsideSplitGroup: .ignored)

    /// The documented future slot, not wired to any setting. Restores the old
    /// Space swipe *outside* a group while cards keep it inside one. Left here
    /// because the choice is a product decision that may be revisited, and the
    /// routing that would carry it already exists.
    static let contextual = MobileToolbarSwipeMode(name: "contextual", outsideSplitGroup: .adjacentSpace)

    /// What ships.
    static let shipping = cardsOnly

    // MARK: - Variables

    let name: String
    /// Where a swipe goes outside a split group. Inside one it always pages cards.
    let outsideSplitGroup: MobileToolbarSwipeDestination

    // MARK: - Initializers

    private init(name: String, outsideSplitGroup: MobileToolbarSwipeDestination) {
        self.name = name
        self.outsideSplitGroup = outsideSplitGroup
    }

    // MARK: - Actions - Swipe

    func destination(isInSplitGroup: Bool) -> MobileToolbarSwipeDestination {
        isInSplitGroup ? .adjacentCard : outsideSplitGroup
    }

    // MARK: - Actions - Identity

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.name == rhs.name
    }
}
