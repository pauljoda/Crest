import SwiftUI

/// Everything a folder group draws itself from, on every shell.
///
/// What differs between a pointer shell and a touch one is read from
/// `BrowserSidebarInteractionPolicy` rather than from which target compiled the
/// file. What the two shells genuinely cannot share — where a page lives, what
/// opening a tab means to the host, how a tab gets home — arrives through the
/// list context the host binds.
@MainActor
struct BrowserFolderGroupConfiguration {
    // MARK: - Variables

    let sidebarInteraction: BrowserSidebarInteractionState
    let folder: FolderStateModel
    /// How many folders hold this one.
    let depth: Int
    let context: BrowserSidebarListContext
    /// The Space the group was drawn for, as it stood then. An action checks
    /// it against the live Space, so a group drawn before a profile was
    /// replaced can never act for the replacement.
    let assignment: BrowserSpaceRuntimeAssignment
    var spacePresentation: SidebarSpacePresentation? = nil

    var spaceID: SpaceID { assignment.spaceID }
    var profileID: UUID { assignment.profileID }
    var browser: BrowserStore { context.browser }
    var pageAccess: BrowserSidebarPageAccess { context.pageAccess }
    var spaceAccess: BrowserSpaceAccessController { context.spaceAccess }
    var capabilities: BrowserInteractionCapabilities { context.capabilities }

    /// The list of what the folder holds, as the core publishes it.
    var inside: SidebarListModel { context.space.sidebar.inside(folder.id) }

    var displayBranding: BrowserSpaceBranding? {
        guard let spacePresentation else { return BrowserSpaceBranding(look: context.space.settings.look) }
        return spacePresentation.assignment == assignment ? spacePresentation.branding : nil
    }

    var headerMetrics: BrowserFolderHeaderMetrics {
        BrowserSidebarInteractionPolicy.savedFolderHeaderMetrics(capabilities)
    }

    /// How far the header's own content sits from the leading edge, in the
    /// column the tab rows give their favicons.
    var headerLeadingInset: CGFloat {
        BrowserFolderLayout.headerLeadingInset(
            depth: depth,
            tabRowMetrics: BrowserSidebarInteractionPolicy.tabRowMetrics(
                capabilities
            )
        )
    }

    var folderRuntimeAssignment: BrowserFolderRuntimeAssignment {
        BrowserFolderRuntimeAssignment(
            folderID: folder.id,
            spaceID: spaceID,
            profileID: profileID
        )
    }

    /// Inactive pages retain their normal control appearance while commands
    /// remain guarded by the live selected Space below.
    var isAvailableForDisplay: Bool {
        guard let spacePresentation else { return isCurrentAndUnlocked }
        return spacePresentation.isAvailable(matching: assignment) && context.space.folders.contains(folder.id)
    }

    /// Every action the group offers is refused unless the window shows the
    /// Space the group was drawn for, unlocked, and the Space still holds the
    /// folder.
    var isCurrentAndUnlocked: Bool {
        context.isCurrent(assignment) && context.space.folders.contains(folder.id)
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
        let state = sidebarInteraction.sidebarReorderState
        guard state.isTargetedFolder(folder.id) else { return nil }
        return state.lift?.item
    }

    /// The drag item the folder lifts as. What it holds is captured when the
    /// lift begins, not while the row draws.
    var dragItem: BrowserFolderDragItem {
        BrowserFolderDragItem(folderID: folder.id, spaceID: spaceID, profileID: profileID)
    }

    // MARK: - Initializers

    init(
        sidebarInteraction: BrowserSidebarInteractionState, folder: FolderStateModel, depth: Int,
        context: BrowserSidebarListContext, spacePresentation: SidebarSpacePresentation?
    ) {
        self.sidebarInteraction = sidebarInteraction
        self.folder = folder
        self.depth = depth
        self.context = context
        assignment = context.assignment
        self.spacePresentation = spacePresentation
    }

    // MARK: - Actions - Contents

    /// The tabs the folder holds directly, the ones its own list shows, in
    /// order. Reading it observes the folder's list.
    var folderTabIDs: [TabID] {
        inside.rows.filter { !$0.kind.opensList }.flatMap(\.members)
    }

    /// The tab the window shows, when the folder holds it directly. Reading it
    /// observes only this folder's tabs' slots of the window's shown tabs.
    var shownFolderTabID: TabID? {
        folderTabIDs.first { context.window.shownTabIDs.contains($0) }
    }

    var residentFolderTabIDs: [TabID] {
        folderTabIDs.filter { pageAccess.containsResidentPage($0) }
    }

    /// Read inside the body so Observation tracks residency, which is
    /// otherwise invisible to it.
    var residencyRevision: Int {
        pageAccess.residencyRevision()
    }

    /// The one row a collapsed folder keeps on screen, the row of its own list
    /// that holds the tab it kept, while that tab still holds a page. A folder
    /// that collapses over the shown tab does not evict it, so the row stays
    /// reachable rather than disappearing under the header. If the tab belongs
    /// to a split the sidebar shows as a row, the whole split stays.
    func keptCollapsedItem(for state: BrowserCollapsedFolderTabVisibilityState) -> BrowserSidebarListItem? {
        guard let keptTabID = state.keptTabID, pageAccess.containsResidentPage(keptTabID) else { return nil }
        return BrowserSidebarListItem.items(of: inside, in: context.space).first { item in
            switch item.content {
            case .tab(let tab): tab.id == keptTabID
            case .split(_, let members): members.contains { $0.id == keptTabID }
            case .folder: false
            }
        }
    }
}
