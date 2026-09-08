/// Coordinates fixed sidebar motion independently of scroll-event distance.
/// A distinct gesture can replace one pending step while the current step settles.
struct SpacePagerTransition {
    private(set) var spaceID: SpaceID
    private(set) var generation: UInt = 0
    private(set) var isAnimating = false
    private var pendingStep: BrowserSpaceSwipeDirection?

    init(spaceID: SpaceID) {
        self.spaceID = spaceID
    }

    mutating func request(_ direction: BrowserSpaceSwipeDirection) -> BrowserSpaceSwipeDirection? {
        guard isAnimating else { return direction }
        pendingStep = direction
        return nil
    }

    /// An external selection supersedes any queued gesture. The caller still
    /// activates resident web content immediately; this state owns chrome only.
    mutating func begin(spaceID: SpaceID) -> UInt {
        generation &+= 1
        self.spaceID = spaceID
        isAnimating = true
        pendingStep = nil
        return generation
    }

    mutating func finish(generation: UInt) -> BrowserSpaceSwipeDirection? {
        guard self.generation == generation else { return nil }
        isAnimating = false
        defer { pendingStep = nil }
        return pendingStep
    }

    mutating func cancel(spaceID: SpaceID) {
        generation &+= 1
        self.spaceID = spaceID
        isAnimating = false
        pendingStep = nil
    }
}
