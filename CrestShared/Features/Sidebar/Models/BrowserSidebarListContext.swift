import SwiftUI

/// Everything the lists of one Space's sidebar draw from and act through, the
/// same for every row of that Space: the Space and the window as the read
/// model keeps them, the images tabs wear, and the collaborators a row acts
/// through. A row reads what it shows from its own objects, so the context
/// never changes while the Space stays on screen.
///
/// Two contexts are equal when they name the same objects. The actions a
/// context carries reach only those objects and the Space's identity, which
/// is why comparing them is not needed: SwiftUI leaves a row alone when its
/// parent hands it the same objects again.
struct BrowserSidebarListContext {
    // MARK: - Variables

    let space: SpaceModel
    let window: WindowStateModel
    let favicons: FaviconAssets
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    let pageAccess: BrowserSidebarPageAccess
    let tabActions: BrowserSidebarTabActions
    let capabilities: BrowserInteractionCapabilities
    /// The namespace each section's rows anchor the page they open in, where
    /// the shell anchors that section's rows at all.
    var promotionNamespaces: [TabPlacement: Namespace.ID] = [:]
    /// What opening a tab means to the host. The rows decide *whether*; the
    /// host decides what appears.
    let select: (TabID) -> Void
    /// How a saved or pinned tab gets back to the page it was saved from, where
    /// the host offers it.
    var restoreSavedLocation: ((TabID) -> Void)? = nil

    /// The Space as the actions name it. A Space keeps its profile while it is
    /// on screen; a new profile is a new page.
    @MainActor var assignment: BrowserSpaceRuntimeAssignment {
        BrowserSpaceRuntimeAssignment(spaceID: space.id, profileID: space.profileID)
    }

    @MainActor var profileID: UUID { space.profileID }

    // MARK: - Actions - Reading

    /// The namespace the rows of `section` anchor their pages in.
    func promotionNamespace(for section: TabPlacement) -> Namespace.ID? {
        promotionNamespaces[section]
    }

    /// Whether the tab holds a resident page in this window. Reading it
    /// observes the page layer's residency.
    @MainActor func isLoaded(_ tabID: TabID) -> Bool {
        pageAccess.containsResidentPage(tabID)
    }

    /// Whether the window shows this Space, unlocked, so its rows may act.
    @MainActor var isCurrentAndUnlocked: Bool {
        isCurrent(assignment)
    }

    /// Whether the window shows the Space `assignment` names, unlocked, with
    /// the same profile, so a row drawn for it may act. A row captures its
    /// assignment when it draws; a profile replaced since refuses it. Reading
    /// it observes which Space the window shows, the Space's membership and
    /// profile, and the Space's lock.
    @MainActor func isCurrent(_ assignment: BrowserSpaceRuntimeAssignment) -> Bool {
        guard window.shownSpaceID == assignment.spaceID, browser.spaceModel(assignment.spaceID) === space,
            space.profileID == assignment.profileID
        else { return false }
        return !spaceAccess.isLocked(space)
    }

    /// Whether a row drawn for the tab `assignment` names may act on it: the
    /// window shows its Space, unlocked, and the Space still holds the tab.
    @MainActor func isTabCurrent(_ assignment: BrowserTabRuntimeAssignment) -> Bool {
        isCurrent(BrowserSpaceRuntimeAssignment(spaceID: assignment.spaceID, profileID: assignment.profileID))
            && space.tabs.contains(assignment.tabID)
    }

    // MARK: - Actions - Tabs

    @MainActor func unload(_ tabID: TabID) {
        pageAccess.unloadPage(tabID, assignment)
    }

    @MainActor func pullNewIcon(_ tabID: TabID) {
        let actions = tabActions
        Task { await actions.pullNewIcon(for: tabID) }
    }
}

extension BrowserSidebarListContext: Equatable {
    static func == (lhs: BrowserSidebarListContext, rhs: BrowserSidebarListContext) -> Bool {
        lhs.space === rhs.space && lhs.window === rhs.window && lhs.favicons === rhs.favicons
            && lhs.browser === rhs.browser && lhs.spaceAccess === rhs.spaceAccess
            && lhs.capabilities == rhs.capabilities && lhs.promotionNamespaces == rhs.promotionNamespaces
            && (lhs.restoreSavedLocation == nil) == (rhs.restoreSavedLocation == nil)
    }
}
