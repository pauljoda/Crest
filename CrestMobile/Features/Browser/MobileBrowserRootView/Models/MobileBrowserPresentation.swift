import CoreGraphics

/// How much room a window has. A compact window shows one thing at a time:
/// its sidebar is the full-screen tab viewer, and the page comes up over it.
/// A regular window keeps its sidebar beside the page. Each size carries what
/// differs between the two, so the models and views that lay a window out ask
/// it instead of asking which one it is.
struct MobileBrowserPresentation: Equatable, Sendable {
    // MARK: - Static Variables

    static let compact: MobileBrowserPresentation = MobileBrowserPresentation(
        name: "compact",
        presentsPageOverTabViewer: true,
        overlayTopPadding: MobileBrowserRootLayout.compactOverlayTopPadding,
        revealsSidebar: { $0.showTabViewer() },
        togglesSidebar: { $0.toggleCompactSidebar(reduceMotion: $1) },
        presentsHistory: { content in
            guard let space = content.browser.shownSpace, !content.spaceAccess.isLocked(space) else { return }
            content.historyAssignment = BrowserSpaceRuntimeAssignment(space: space)
        },
        beginsNewTab: { content in
            content.model.beginCompactNewTab()
            content.isAddressEditing = false
            content.addressFocusRequest &+= 1
        },
        opensLocation: { content in
            if content.navigation.defersPageActivation {
                content.model.activateSelectedTab()
            }
            Task { @MainActor in
                await Task.yield()
                content.isAddressEditing = true
                content.addressFocusRequest &+= 1
            }
        }
    )

    static let regular: MobileBrowserPresentation = MobileBrowserPresentation(
        name: "regular",
        presentsPageOverTabViewer: false,
        overlayTopPadding: MobileBrowserRootLayout.regularOverlayTopPadding,
        revealsSidebar: { $0.showRegularSidebar() },
        togglesSidebar: { $0.toggleRegularSidebar(reduceMotion: $1) },
        presentsHistory: { content in
            content.model.revealSidebarForUtilityCommand(presentation: .regular)
            content.navigation.utilityPresentation.present(.history)
        },
        beginsNewTab: { content in
            // The Start Page searches in its own field; any other page opens
            // the overlay palette.
            if content.showsStartPage {
                content.focusStartPageCommandPalette()
            } else {
                content.commandPaletteMode = .newTab
            }
        },
        opensLocation: { content in
            content.showRegularSidebar()
            if content.showsStartPage {
                content.focusStartPageCommandPalette()
            } else {
                content.commandPaletteMode = .editLocation(content.address)
            }
        }
    )

    // MARK: - Variables

    let name: String

    /// Whether the window's sidebar is the full-screen tab viewer, with the
    /// page presented over it. A regular window instead keeps its sidebar
    /// beside the page, shows the overlay command palette and the window's
    /// atmosphere, and owns its sidebar's width and visibility.
    let presentsPageOverTabViewer: Bool

    /// How far below the top edge transient feedback floats.
    let overlayTopPadding: CGFloat

    private let revealsSidebar: @MainActor @Sendable (MobileBrowserNavigationState) -> Void
    private let togglesSidebar: @MainActor @Sendable (MobileBrowserRootModel, Bool) -> Void
    private let presentsHistory: @MainActor @Sendable (MobileBrowserRootContent) -> Void
    private let beginsNewTab: @MainActor @Sendable (MobileBrowserRootContent) -> Void
    private let opensLocation: @MainActor @Sendable (MobileBrowserRootContent) -> Void

    /// How the window shows Settings.
    @MainActor
    var settingsStyle: MobileBrowserSettingsStyle {
        presentsPageOverTabViewer ? .sheet : .embedded
    }

    // MARK: - Initializers

    private init(
        name: String,
        presentsPageOverTabViewer: Bool,
        overlayTopPadding: CGFloat,
        revealsSidebar: @escaping @MainActor @Sendable (MobileBrowserNavigationState) -> Void,
        togglesSidebar: @escaping @MainActor @Sendable (MobileBrowserRootModel, Bool) -> Void,
        presentsHistory: @escaping @MainActor @Sendable (MobileBrowserRootContent) -> Void,
        beginsNewTab: @escaping @MainActor @Sendable (MobileBrowserRootContent) -> Void,
        opensLocation: @escaping @MainActor @Sendable (MobileBrowserRootContent) -> Void
    ) {
        self.name = name
        self.presentsPageOverTabViewer = presentsPageOverTabViewer
        self.overlayTopPadding = overlayTopPadding
        self.revealsSidebar = revealsSidebar
        self.togglesSidebar = togglesSidebar
        self.presentsHistory = presentsHistory
        self.beginsNewTab = beginsNewTab
        self.opensLocation = opensLocation
    }

    // MARK: - Actions - Sidebar

    /// Brings the sidebar up for a list a command asked for.
    @MainActor
    func revealSidebar(on navigation: MobileBrowserNavigationState) {
        revealsSidebar(navigation)
    }

    @MainActor
    func toggleSidebar(on model: MobileBrowserRootModel, reduceMotion: Bool) {
        togglesSidebar(model, reduceMotion)
    }

    // MARK: - Actions - Commands

    @MainActor
    func presentHistory(in content: MobileBrowserRootContent) {
        presentsHistory(content)
    }

    @MainActor
    func beginNewTab(in content: MobileBrowserRootContent) {
        beginsNewTab(content)
    }

    @MainActor
    func openLocation(in content: MobileBrowserRootContent) {
        opensLocation(content)
    }

    // MARK: - Actions - Identity

    static func == (lhs: MobileBrowserPresentation, rhs: MobileBrowserPresentation) -> Bool {
        lhs.name == rhs.name
    }
}
