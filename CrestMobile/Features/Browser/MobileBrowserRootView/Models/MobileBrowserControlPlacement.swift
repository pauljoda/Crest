import SwiftUI

/// Where a window's page and Space controls live: in Crest's own chrome, or in
/// the system toolbar on iPhone Duo, down the side of the window or, with the
/// display held upright, across the band its top keeps for the status bar and
/// a top bar. The controls move rather than repeat, so the chrome that draws
/// them asks the placement instead of asking which device it is on.
struct MobileBrowserControlPlacement: Equatable, Sendable {
    // MARK: - Types

    /// How long a control stays in a system bar that runs out of room, the
    /// highest folding into the bar's overflow menu last: history, reload and
    /// the sidebar toggle, then the rest from leading to trailing, with
    /// Settings the first to go.
    struct Rank: Sendable {
        static let navigation = Rank(stepsBelowHighest: 0)
        static let newTab = Rank(stepsBelowHighest: 1)
        static let pageActions = Rank(stepsBelowHighest: 2)
        static let privateBrowsing = Rank(stepsBelowHighest: 3)
        static let commonLists = Rank(stepsBelowHighest: 4)
        static let downloads = Rank(stepsBelowHighest: 5)
        static let settings = Rank(stepsBelowHighest: 6)

        let stepsBelowHighest: Int

        @available(iOS 27.0, *)
        var visibilityPriority: ToolbarItemVisibilityPriority {
            (0..<stepsBelowHighest).reduce(.high) { priority, _ in
                ToolbarItemVisibilityPriority(lowerThan: priority)
            }
        }
    }

    // MARK: - Static Variables

    static let chrome = MobileBrowserControlPlacement(
        name: "chrome",
        movesControlsToToolbar: false,
        runsDownSide: false
    )

    static let sideToolbar = MobileBrowserControlPlacement(
        name: "sideToolbar",
        movesControlsToToolbar: true,
        runsDownSide: true
    )

    static let topBar = MobileBrowserControlPlacement(
        name: "topBar",
        movesControlsToToolbar: true,
        runsDownSide: false
    )

    // MARK: - Variables

    let name: String

    /// Whether the controls are toolbar items rather than drawn in the chrome.
    let movesControlsToToolbar: Bool

    /// Whether the toolbar runs down the side of the window, clear of the
    /// status bar and the camera, rather than across its top. Its top group
    /// takes the page controls and its bottom group the Space's.
    let runsDownSide: Bool

    /// Whether the controls ride in the bar across the window's top: one run
    /// from its leading end, the page's controls and then the Space's, so the
    /// bar weighs them all against each other as it runs out of room.
    var carriesControlsInTopBar: Bool {
        movesControlsToToolbar && !runsDownSide
    }

    /// Where the page's controls go as toolbar items: the side column's top
    /// group, or the start of the top bar's run.
    var pageControlsPlacement: ToolbarItemPlacement {
        .topBarTrailing
    }

    /// Where the Space's controls go as toolbar items: the side column's
    /// bottom group, or on along the top bar's run.
    var spaceControlsPlacement: ToolbarItemPlacement {
        runsDownSide ? .bottomBar : .topBarTrailing
    }

    /// The system bars' visibility: shown only to carry the moved controls.
    var barVisibility: Visibility {
        movesControlsToToolbar ? .automatic : .hidden
    }

    // MARK: - Initializers

    private init(name: String, movesControlsToToolbar: Bool, runsDownSide: Bool) {
        self.name = name
        self.movesControlsToToolbar = movesControlsToToolbar
        self.runsDownSide = runsDownSide
    }

    // MARK: - Actions - Sizing

    /// The placement for a window whose system bars prefer `verticalEdge`, or
    /// that lays them out across the top and bottom when there is none. A
    /// display that keeps a band across its top for the status bar and a top
    /// bar puts the controls there; any other keeps them in the chrome.
    static func fitting(
        verticalEdge: HorizontalEdge?,
        sharesTopBandWithStatusBar: Bool
    ) -> MobileBrowserControlPlacement {
        if verticalEdge != nil { return .sideToolbar }
        return sharesTopBandWithStatusBar ? .topBar : .chrome
    }

    // MARK: - Actions - Layout

    /// The page frame's insets. Where the controls move to the side toolbar the
    /// display rounds its corners far more than a page frame does, so a page
    /// that reaches the window's leading edge stands off it, and off the top
    /// and bottom, by the layout margin, and its corners clear the display's.
    func pageInsets(_ insets: EdgeInsets) -> EdgeInsets {
        guard runsDownSide, insets.leading > 0 else { return insets }
        let margin = MobileBrowserRootLayout.displayEdgeMargin
        return EdgeInsets(
            top: max(insets.top, margin),
            leading: max(insets.leading, margin),
            bottom: max(insets.bottom, margin),
            trailing: insets.trailing
        )
    }

    // MARK: - Actions - Identity

    static func == (lhs: MobileBrowserControlPlacement, rhs: MobileBrowserControlPlacement) -> Bool {
        lhs.name == rhs.name
    }
}

extension EnvironmentValues {
    @Entry var mobileBrowserControlPlacement: MobileBrowserControlPlacement = .chrome
}

extension ToolbarContent {
    /// The content, folding into its bar's overflow menu at `rank` where the
    /// system ranks a bar's items.
    @ToolbarContentBuilder
    func collapsing(at rank: MobileBrowserControlPlacement.Rank) -> some ToolbarContent {
        if #available(iOS 27.0, *) {
            visibilityPriority(rank.visibilityPriority)
        } else {
            self
        }
    }
}
