import Observation

/// Owns the interaction state shared by one window's sidebar and page surfaces.
@Observable
@MainActor
final class BrowserSidebarInteractionState: BrowserStoreInteractionObserving {
    let tabDragState = BrowserTabDragState()
    let folderDragState = BrowserFolderDragState()
    let sidebarReorderState = BrowserSidebarReorderState()
    /// The folder whose title the window's sidebar is editing, such as one it
    /// just made. The folder's row starts editing when it appears.
    var editingFolderRequest: BrowserFolderRuntimeAssignment?
    @ObservationIgnored weak var sidebarSpaceAccess: BrowserSpaceAccessController?
    @ObservationIgnored private var collapsedFolders: [BrowserFolderRuntimeAssignment: BrowserSidebarFolderVisibility] =
        [:]

    // SwiftUI can evaluate a discarded root initializer while retaining the visible model.
    static func connected(to browser: BrowserStore) -> BrowserSidebarInteractionState {
        if let existing = browser.interactionObserver as? BrowserSidebarInteractionState { return existing }
        let interaction = BrowserSidebarInteractionState()
        browser.interactionObserver = interaction
        return interaction
    }

    private init() {}

    func cancel() {
        tabDragState.end()
        folderDragState.end()
        sidebarReorderState.cancel()
    }

    func browserWillResetSession() {
        cancel()
        prune(keeping: [])
    }

    /// A folder's kept resident row belongs to the window, not a disposable
    /// SwiftUI row. Separate boxes keep updates local to the affected folder.
    func collapsedFolderVisibility(for assignment: BrowserFolderRuntimeAssignment) -> BrowserSidebarFolderVisibility {
        if let existing = collapsedFolders[assignment] { return existing }
        let visibility = BrowserSidebarFolderVisibility()
        collapsedFolders[assignment] = visibility
        return visibility
    }

    /// Brings every folder's kept row in step with the Space as the read
    /// model holds it: the tabs each folder holds directly, the shown tab and
    /// which tabs hold a page.
    func reconcileCollapsedFolders(in space: SpaceModel, selectedTabID: TabID?, residentTabIDs: Set<TabID>) {
        for folder in space.folders.models {
            let assignment = BrowserFolderRuntimeAssignment(
                folderID: folder.id, spaceID: space.id, profileID: space.profileID)
            let tabIDs = space.sidebar.inside(folder.id).rows.filter { !$0.kind.opensList }.flatMap(\.members)
            reconcileCollapsedFolder(
                assignment, isExpanded: !folder.isCollapsed, selectedTabID: selectedTabID,
                folderTabIDs: tabIDs,
                residentFolderTabIDs: tabIDs.filter { residentTabIDs.contains($0) })
        }
    }

    func reconcileCollapsedFolder(
        _ assignment: BrowserFolderRuntimeAssignment, isExpanded: Bool, selectedTabID: TabID?,
        folderTabIDs: [TabID], residentFolderTabIDs: [TabID]
    ) {
        let visibility = collapsedFolderVisibility(for: assignment)
        var next = visibility.state
        if visibility.wasExpanded != isExpanded {
            next.expansionDidChange(
                isExpanded: isExpanded, selectedTabID: selectedTabID, folderTabIDs: folderTabIDs)
        }
        next.residencyDidChange(
            isExpanded: isExpanded, selectedTabID: selectedTabID, residentFolderTabIDs: residentFolderTabIDs)
        visibility.wasExpanded = isExpanded
        if next != visibility.state { visibility.state = next }
    }

    /// Forgets the kept rows of folders none of `spaces` holds any longer.
    func pruneCollapsedFolders(keepingFoldersOf spaces: [SpaceModel]) {
        let kept = spaces.flatMap { space in
            space.folders.models.map {
                BrowserFolderRuntimeAssignment(folderID: $0.id, spaceID: space.id, profileID: space.profileID)
            }
        }
        prune(keeping: kept)
    }

    private func prune(keeping kept: [BrowserFolderRuntimeAssignment]) {
        let valid = Set(kept)
        for assignment in Array(collapsedFolders.keys) where !valid.contains(assignment) {
            let removed = collapsedFolders.removeValue(forKey: assignment)
            removed?.state = BrowserCollapsedFolderTabVisibilityState()
        }
    }

    func browserDidMoveTab(from source: BrowserTabRuntimeAssignment, to destination: BrowserSpaceRuntimeAssignment) {
        guard tabDragState.isDragging(source) else { return }
        tabDragState.relocate(to: destination)
    }
}

@Observable
@MainActor
final class BrowserSidebarFolderVisibility {
    var state = BrowserCollapsedFolderTabVisibilityState()
    @ObservationIgnored var wasExpanded: Bool?
}
