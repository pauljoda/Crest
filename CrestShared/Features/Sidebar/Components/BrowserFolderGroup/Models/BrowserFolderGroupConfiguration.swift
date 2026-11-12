import SwiftUI

/// Everything a folder group draws itself from, on every shell.
///
/// What differs between a pointer shell and a touch one is read from
/// `BrowserInteractionCapabilities` rather than from which target compiled the
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
    /// The tabs a collapsed folder around this one keeps on screen, which
    /// this folder shows the way to in place of its contents, or nil when it
    /// draws as itself.
    let inheritedKeptTabIDs: Set<UUID>?

    var spaceID: UUID { assignment.spaceID }
    var profileID: UUID { assignment.profileID }
    var browser: BrowserStore { context.browser }
    var pageAccess: BrowserSidebarPageAccess { context.pageAccess }
    var spaceAccess: BrowserSpaceAccessController { context.spaceAccess }
    var capabilities: BrowserInteractionCapabilities { context.capabilities }

    /// The list of what the folder holds, as the core publishes it.
    var inside: SidebarListModel { context.space.sidebar.inside(folder.id) }

    /// Whether the folder draws everything it holds: it is open, and no
    /// collapsed folder around it is showing only the way to its kept tabs.
    var showsAllContents: Bool { !folder.isCollapsed && inheritedKeptTabIDs == nil }

    var displayBranding: SpaceBranding? {
        guard let spacePresentation else { return context.space.settings.look }
        return spacePresentation.assignment == assignment ? spacePresentation.branding : nil
    }

    var headerMetrics: BrowserFolderHeaderMetrics {
        capabilities.savedFolderHeaderMetrics
    }

    /// How far the header's own content sits from the leading edge, in the
    /// column the tab rows give their favicons.
    var headerLeadingInset: CGFloat {
        BrowserFolderLayout.headerLeadingInset(
            depth: depth,
            tabRowMetrics: capabilities.tabRowMetrics
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

    /// The drag item the folder lifts as. What it holds is captured when the
    /// lift begins, not while the row draws.
    var dragItem: BrowserFolderDragItem {
        BrowserFolderDragItem(folderID: folder.id, spaceID: spaceID, profileID: profileID)
    }

    // MARK: - Initializers

    init(
        sidebarInteraction: BrowserSidebarInteractionState, folder: FolderStateModel, depth: Int,
        context: BrowserSidebarListContext, spacePresentation: SidebarSpacePresentation?,
        inheritedKeptTabIDs: Set<UUID>? = nil
    ) {
        self.sidebarInteraction = sidebarInteraction
        self.folder = folder
        self.depth = depth
        self.context = context
        assignment = context.assignment
        self.spacePresentation = spacePresentation
        self.inheritedKeptTabIDs = inheritedKeptTabIDs
    }

    // MARK: - Actions - Contents

    /// Every tab the folder holds, however deep, in the order the sidebar
    /// lists them. Reading it observes the folder's lists.
    var folderTabIDs: [UUID] {
        context.space.tabIDs(inFolder: folder.id)
    }

    /// The tab the window shows, when the folder holds it. Reading it observes
    /// only this folder's tabs' slots of the window's shown tabs.
    var shownFolderTabID: UUID? {
        folderTabIDs.first { context.window.shownTabIDs.contains($0) }
    }

    var residentFolderTabIDs: [UUID] {
        folderTabIDs.filter { pageAccess.containsResidentPage($0) }
    }

    /// Read inside the body so Observation tracks residency, which is
    /// otherwise invisible to it.
    var residencyRevision: Int {
        pageAccess.residencyRevision()
    }

    /// The tabs the folder keeps on screen in place of its contents, of those
    /// it still holds: the ones a collapsed folder around it keeps, or the
    /// ones it kept itself when it closed. They stay whether or not they hold
    /// a page, until the folder opens. Empty while the folder draws its
    /// contents, or keeps none.
    func keptTabIDs(for state: BrowserCollapsedFolderTabVisibilityState) -> Set<UUID> {
        guard let kept = inheritedKeptTabIDs ?? (folder.isCollapsed ? state.keptTabIDs : nil), !kept.isEmpty else {
            return []
        }
        return kept.intersection(folderTabIDs)
    }
}
