enum MobileBrowserPresentation: Equatable, Sendable {
    case compact
    case regular
}

enum MobileBrowserSpaceSwitchDestination: Equatable {
    case tabViewer
    case selectedPage
}

enum MobileCompactChromeTransition: Equatable, Sendable {
    case revealTabViewer
    case revealPage
}

enum MobileCompactPagePresentationPhase: Equatable {
    case tabViewer
    case presentingPage
    case page
}

/// Where the compact chrome's upward reveal puts the sidebar.
enum MobileCompactSidebarRevealDestination: CaseIterable, Equatable, Sendable {
    /// The full-screen tab viewer, which on a narrow phone *is* the docked
    /// sidebar. The page it was swiped from is left behind.
    case tabViewer
    /// The sidebar floating over the page, which stays on screen underneath it.
    case floatingSidebar
}

enum MobileStartPageForegroundTone: Equatable, Sendable {
    case onBrand
}

enum MobileStartPageSearchDestination: Equatable, Sendable {
    case embeddedStartPage
    case overlay
}

struct MobileTabPromotionTarget: Equatable {
    let tabID: TabID
    let placement: TabPlacement
}

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
