/// Where the compact chrome's upward reveal puts the sidebar.
///
/// The gesture has one meaning — bring the sidebar up — and the sidebar has
/// three placements. A narrow phone's docked sidebar *is* the full-screen tab
/// viewer, so the swipe has always ended there and still does; the two undocked
/// placements own that same sidebar over a page that stays on screen, and the
/// swipe belongs to them the same way.
///
/// Reaching this toolbar undocked takes a Split View.
/// `MobileBrowserRootContent.showsCompactPageToolbar` puts the compact toolbar
/// up for a docked sidebar *or* a presented split, so a floating or collapsed
/// sidebar only has a toolbar to swipe while a group is on show. Sending the
/// swipe to the full-screen viewer from there took the window out of its split
/// and re-docked the sidebar in one move — two placement changes the finger
/// never asked for, and no way back to either except by undoing both by hand.
///
/// Keyed on the placement rather than on the split, because that is the rule
/// itself rather than the one case that exposes it: the sidebar comes up where
/// the window already keeps it. Answering the split directly would say the same
/// thing today and stop being true the moment anything else puts this toolbar on
/// screen undocked.
struct MobileCompactSidebarRevealDestination: Equatable, Sendable {
    // MARK: - Static Variables

    /// The full-screen tab viewer, which on a narrow phone *is* the docked
    /// sidebar. The page it was swiped from is left behind.
    ///
    /// The tab viewer shows a Space's lists as sheets, so a list a command
    /// asks for comes up as one over whatever the window shows, without
    /// leaving the page.
    static let tabViewer = MobileCompactSidebarRevealDestination(
        name: "tabViewer", reveals: { $0.showTabViewer() },
        presentsList: { content, surface in content.presentListSheet(surface) })
    /// The sidebar floating over the page, which stays on screen underneath it.
    /// A list a command asks for slides in with it, in place of the tabs.
    static let floatingSidebar = MobileCompactSidebarRevealDestination(
        name: "floatingSidebar",
        reveals: { content in
            content.dismissAddressFocus()
            content.showRegularSidebar()
        },
        presentsList: { content, surface in
            content.dismissAddressFocus()
            content.showRegularSidebar()
            content.navigation.utilityPresentation.present(surface)
        })

    // MARK: - Variables

    let name: String
    private let reveals: @MainActor @Sendable (MobileBrowserRootContent) -> Void
    private let presentsList: @MainActor @Sendable (MobileBrowserRootContent, BrowserUtilitySurface) -> Void

    // MARK: - Initializers

    private init(
        name: String,
        reveals: @escaping @MainActor @Sendable (MobileBrowserRootContent) -> Void,
        presentsList: @escaping @MainActor @Sendable (MobileBrowserRootContent, BrowserUtilitySurface) -> Void
    ) {
        self.name = name
        self.reveals = reveals
        self.presentsList = presentsList
    }

    // MARK: - Actions - Reveal

    /// Where the reveal goes from a sidebar at `sidebarPresentation`.
    static func destination(
        sidebarPresentation: BrowserSidebarPresentation
    ) -> MobileCompactSidebarRevealDestination {
        sidebarPresentation == .docked ? .tabViewer : .floatingSidebar
    }

    /// Brings the sidebar up here.
    @MainActor
    func reveal(in content: MobileBrowserRootContent) {
        reveals(content)
    }

    /// Brings one of the shown Space's lists up here.
    @MainActor
    func presentList(_ surface: BrowserUtilitySurface, in content: MobileBrowserRootContent) {
        presentsList(content, surface)
    }

    // MARK: - Actions - Identity

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.name == rhs.name
    }
}
