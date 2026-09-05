import SwiftUI

/// Everything a saved folder group draws itself from, on every shell.
///
/// What differs between a pointer shell and a touch one is read from
/// `BrowserSidebarInteractionPolicy` rather than from which target compiled the
/// file. What the two shells genuinely cannot share — where a page lives, what
/// opening a tab means to the host, how a tab gets home — arrives as the page
/// seam and a handful of closures the host binds.
@MainActor
struct BrowserFolderGroupConfiguration {
    let node: BrowserFolderNode
    let tabs: [BrowserTab]
    var subtreeTabIDs: [TabID] = []
    let spaceID: SpaceID
    let profileID: UUID
    let selectedTabID: TabID?
    let browser: BrowserStore
    let pageAccess: BrowserSidebarPageAccess
    let spaceAccess: BrowserSpaceAccessController
    let capabilities: BrowserInteractionCapabilities
    let promotionNamespace: Namespace.ID?
    let pullNewIcon: ((TabID) -> Void)?
    let restoreSavedLocation: ((TabID) -> Void)?
    let select: (TabID) -> Void

    var folder: BrowserFolder { node.folder }

    var assignment: BrowserSpaceRuntimeAssignment {
        BrowserSpaceRuntimeAssignment(spaceID: spaceID, profileID: profileID)
    }

    var headerMetrics: BrowserFolderHeaderMetrics {
        BrowserSidebarInteractionPolicy.savedFolderHeaderMetrics(capabilities)
    }

    /// How far the header's own content sits from the leading edge, in the
    /// column the tab rows give their favicons.
    var headerLeadingInset: CGFloat {
        BrowserFolderLayout.headerLeadingInset(
            depth: node.depth,
            tabRowMetrics: BrowserSidebarInteractionPolicy.tabRowMetrics(
                capabilities
            )
        )
    }

    /// How far a row inside this folder is indented. Tab rows and stacked
    /// split-group rows share it so a group never breaks the nesting rhythm.
    var rowLeadingInset: CGFloat {
        BrowserFolderLayout.rowLeadingInset(depth: node.depth)
    }

    /// The folder's rows, with contiguous split runs folded into group rows.
    var items: [BrowserSidebarTabListItem] {
        BrowserSidebarTabListItemPolicy.items(for: tabs)
    }

    /// The row each of the folder's rows would insert in front of, which only
    /// a shell that draws its insertion line on the rows themselves reads.
    /// Everywhere else the section's own zone carries the whole answer, and
    /// building the map would be work nothing looks at.
    var followingTabIDs: [TabID: TabID] {
        guard capabilities.showsRowDropIndicators else { return [:] }
        return BrowserTabRowInsertionPolicy.followingTabIDs(in: tabs)
    }

    var folderRuntimeAssignment: BrowserFolderRuntimeAssignment {
        BrowserFolderRuntimeAssignment(
            folderID: folder.id,
            spaceID: spaceID,
            profileID: profileID
        )
    }

    var isCurrentAndUnlocked: Bool {
        BrowserSidebarAccessPolicy.selectedUnlockedSpace(
            matching: assignment,
            in: browser,
            accessController: spaceAccess
        ) != nil
    }

    /// What releasing the lift in flight would file inside this folder, if
    /// anything would.
    ///
    /// The reorder state resolves the target from the measured geometry — a
    /// collapsed folder registers the middle band of its row as a nesting zone —
    /// so the folder only has to draw the answer. Nothing but a tab or a folder
    /// can appear here: a split group moves as one block and refuses folder
    /// zones outright.
    var nestingLift: BrowserSidebarReorderItem? {
        let state = browser.sidebarReorderState
        guard state.isTargetedFolder(folder.id) else { return nil }
        return state.lift?.item
    }

    func isLoaded(_ tabID: TabID) -> Bool {
        pageAccess.containsResidentPage(tabID)
    }

    func unload(_ tabID: TabID) {
        pageAccess.unloadPage(tabID, assignment)
    }

    /// Read inside the body so Observation tracks residency, which is
    /// otherwise invisible to it.
    var residencyRevision: Int {
        pageAccess.residencyRevision()
    }

    /// The one tab a collapsed folder keeps on screen, while it still holds a
    /// page. A folder that collapses over the selected tab does not evict it,
    /// so the row stays reachable rather than disappearing under the header.
    func keptCollapsedItem(
        for state: BrowserCollapsedFolderTabVisibilityState
    ) -> BrowserSidebarTabListItem? {
        guard let keptTabID = state.keptTabID,
            pageAccess.containsResidentPage(keptTabID)
        else {
            return nil
        }
        return BrowserSidebarTabListItemPolicy.collapsedItem(
            keeping: keptTabID,
            in: tabs
        )
    }

    var residentFolderTabIDs: [TabID] {
        tabs.compactMap { tab in
            pageAccess.containsResidentPage(tab.id) ? tab.id : nil
        }
    }
}
