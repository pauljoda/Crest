import Observation

/// Owns the interaction state shared by one window's sidebar and page surfaces.
@Observable
@MainActor
final class BrowserSidebarInteractionState: BrowserStoreInteractionObserving {
    let tabDragState = BrowserTabDragState()
    let folderDragState = BrowserFolderDragState()
    let sidebarReorderState = BrowserSidebarReorderState()
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
        pruneCollapsedFolders(in: [])
    }

    /// A folder's kept resident row belongs to the window, not a disposable
    /// SwiftUI row. Separate boxes keep updates local to the affected folder.
    func collapsedFolderVisibility(for assignment: BrowserFolderRuntimeAssignment) -> BrowserSidebarFolderVisibility {
        if let existing = collapsedFolders[assignment] { return existing }
        let visibility = BrowserSidebarFolderVisibility()
        collapsedFolders[assignment] = visibility
        return visibility
    }

    func reconcileCollapsedFolders(in space: BrowserSpace, residentTabIDs: Set<TabID>) {
        let sections = space.tabSections
        for folder in space.folders {
            let assignment = BrowserFolderRuntimeAssignment(
                folderID: folder.id, spaceID: space.id, profileID: space.profile.id)
            let tabs = sections.tabs(in: folder.id)
            reconcileCollapsedFolder(
                assignment, isExpanded: !folder.isCollapsed, selectedTabID: space.selectedTabID,
                folderTabIDs: tabs.map(\.id),
                residentFolderTabIDs: tabs.compactMap { residentTabIDs.contains($0.id) ? $0.id : nil })
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

    func pruneCollapsedFolders(in spaces: [BrowserSpace]) {
        let valid = Set(
            spaces.flatMap { space in
                space.folders.map {
                    BrowserFolderRuntimeAssignment(
                        folderID: $0.id, spaceID: space.id, profileID: space.profile.id)
                }
            })
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
