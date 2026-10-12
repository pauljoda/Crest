/// Where a recognized horizontal toolbar swipe goes.
struct MobileToolbarSwipeDestination: Equatable, Sendable {
    // MARK: - Static Variables

    /// The next or previous card of the presented split, clamped at the ends.
    static let adjacentCard = MobileToolbarSwipeDestination(
        name: "adjacentCard", swipes: { content, direction in content.model.selectAdjacentSplitCard(direction) })
    /// The next or previous Space. Reachable only from
    /// `MobileToolbarSwipeMode.contextual`, which nothing ships with today.
    static let adjacentSpace = MobileToolbarSwipeDestination(
        name: "adjacentSpace",
        swipes: { content, direction in content.model.switchSpace(direction, reduceMotion: content.reduceMotion) })
    /// Recognized and deliberately ignored. The recognizer stays installed —
    /// the same finger travel means something the moment a split is open, and a
    /// gesture that appears only in some states is harder to learn than one that
    /// is simply quiet in others.
    static let ignored = MobileToolbarSwipeDestination(name: "ignored", swipes: { _, _ in })

    // MARK: - Variables

    let name: String
    private let swipes: @MainActor @Sendable (MobileBrowserRootContent, BrowserSpaceSwipeDirection) -> Void

    // MARK: - Initializers

    private init(
        name: String,
        swipes: @escaping @MainActor @Sendable (MobileBrowserRootContent, BrowserSpaceSwipeDirection) -> Void
    ) {
        self.name = name
        self.swipes = swipes
    }

    // MARK: - Actions - Swipe

    /// Goes `direction` from what `content` shows.
    @MainActor
    func swipe(_ direction: BrowserSpaceSwipeDirection, in content: MobileBrowserRootContent) {
        swipes(content, direction)
    }

    // MARK: - Actions - Identity

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.name == rhs.name
    }
}
