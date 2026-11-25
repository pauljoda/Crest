import Foundation
import Observation

/// Owns the interaction state shared by one window's sidebar and page surfaces.
@Observable
@MainActor
final class BrowserSidebarInteractionState: BrowserStoreInteractionObserving {
    let tabDragState = BrowserTabDragState()
    let folderDragState = BrowserFolderDragState()
    let sidebarReorderState = BrowserSidebarReorderState()
    /// The card of the tab the window's sidebar is rested on.
    let tabPreview = BrowserTabPreviewState()
    /// The folder whose title the window's sidebar is editing, such as one it
    /// just made. The folder's row starts editing when it appears.
    var editingFolderRequest: BrowserFolderRuntimeAssignment?
    @ObservationIgnored weak var sidebarSpaceAccess: BrowserSpaceAccessController?
    @ObservationIgnored private var collapsedFolders: [BrowserFolderRuntimeAssignment: BrowserSidebarFolderVisibility] =
        [:]
    /// The window whose core record learns which rows collapsed folders keep.
    @ObservationIgnored private weak var browser: BrowserStore?
    /// The kept rows last reported to the core, by Space.
    @ObservationIgnored private var reportedKeptRows: [UUID: Set<UUID>] = [:]
    /// The saved tabs whose delete control waits after the sidebar unloaded
    /// them, each with the hold that last began. They belong to the window,
    /// not to a row, which the sidebar can build anew as its tab unloads.
    private var deleteHolds: [UUID: UUID] = [:]

    // SwiftUI can evaluate a discarded root initializer while retaining the visible model.
    static func connected(to browser: BrowserStore) -> BrowserSidebarInteractionState {
        if let existing = browser.interactionObserver as? BrowserSidebarInteractionState { return existing }
        let interaction = BrowserSidebarInteractionState()
        interaction.browser = browser
        browser.interactionObserver = interaction
        return interaction
    }

    private init() {}

    // MARK: - Actions - Paging

    /// Whether something in flight owns the horizontal axis, so the Space
    /// strip must not page under it.
    var ownsHorizontalAxis: Bool {
        Self.ownsHorizontalAxis(
            hasSidebarLift: sidebarReorderState.hasLiftInFlight,
            hasTabDrag: tabDragState.item != nil,
            hasFolderDrag: folderDragState.item != nil
        )
    }

    /// Whether something in flight owns the horizontal axis.
    ///
    /// Three sources, because a sidebar item can be picked up three ways and any
    /// of them is spoiled by the strip paging underneath it. The sidebar lift is
    /// named first and separately: it is the only one a touch shell ever raises,
    /// and reading the two pointer drag states alone left the pager live under
    /// every finger drag.
    static func ownsHorizontalAxis(
        hasSidebarLift: Bool,
        hasTabDrag: Bool,
        hasFolderDrag: Bool
    ) -> Bool {
        hasSidebarLift || hasTabDrag || hasFolderDrag
    }

    func cancel() {
        tabDragState.end()
        folderDragState.end()
        sidebarReorderState.cancel()
        tabPreview.dismiss()
    }

    func browserWillResetSession() {
        cancel()
        prune(keeping: [])
    }

    /// The tabs a collapsed folder keeps on screen belong to the window, not a
    /// disposable SwiftUI row. Separate boxes keep updates local to the affected folder.
    func collapsedFolderVisibility(for assignment: BrowserFolderRuntimeAssignment) -> BrowserSidebarFolderVisibility {
        if let existing = collapsedFolders[assignment] { return existing }
        let visibility = BrowserSidebarFolderVisibility()
        collapsedFolders[assignment] = visibility
        return visibility
    }

    func reconcileCollapsedFolder(
        _ assignment: BrowserFolderRuntimeAssignment, isExpanded: Bool, selectedTabID: UUID?,
        folderTabIDs: [UUID], residentFolderTabIDs: [UUID], loadedFolderTabIDs: [UUID]
    ) {
        let visibility = collapsedFolderVisibility(for: assignment)
        var next = visibility.state
        if visibility.wasExpanded != isExpanded {
            next.expansionDidChange(
                isExpanded: isExpanded, selectedTabID: selectedTabID, folderTabIDs: folderTabIDs,
                residentFolderTabIDs: residentFolderTabIDs)
        }
        next.selectionDidChange(isExpanded: isExpanded, selectedTabID: selectedTabID, folderTabIDs: folderTabIDs)
        next.residencyDidChange(
            isExpanded: isExpanded, selectedTabID: selectedTabID, residentFolderTabIDs: residentFolderTabIDs,
            loadedFolderTabIDs: loadedFolderTabIDs)
        visibility.wasExpanded = isExpanded
        if next != visibility.state { visibility.state = next }
        reportKeptRows(in: assignment.spaceID)
    }

    /// Starts renaming the folder `folderID` of `space` where the sidebar draws
    /// it, as a group is named the moment it is made.
    func beginRenaming(folder folderID: UUID, in space: SpaceModel) {
        editingFolderRequest = BrowserFolderRuntimeAssignment(
            folderID: folderID, spaceID: space.id, profileID: space.profileID)
    }

    /// Takes the rows a closed folder keeps again, as though it closed now, as
    /// when it turns into a group or back and its new kind keeps other rows.
    func rekeepCollapsedFolder(
        _ assignment: BrowserFolderRuntimeAssignment, isExpanded: Bool, selectedTabID: UUID?,
        folderTabIDs: [UUID], residentFolderTabIDs: [UUID]
    ) {
        let visibility = collapsedFolderVisibility(for: assignment)
        var next = visibility.state
        next.expansionDidChange(
            isExpanded: isExpanded, selectedTabID: selectedTabID, folderTabIDs: folderTabIDs,
            residentFolderTabIDs: residentFolderTabIDs)
        if next != visibility.state { visibility.state = next }
        reportKeptRows(in: assignment.spaceID)
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
        var spaces: Set<UUID> = []
        for assignment in Array(collapsedFolders.keys) where !valid.contains(assignment) {
            let removed = collapsedFolders.removeValue(forKey: assignment)
            removed?.state = BrowserCollapsedFolderTabVisibilityState()
            spaces.insert(assignment.spaceID)
        }
        for spaceID in spaces { reportKeptRows(in: spaceID) }
    }

    /// Reports to the core the tabs the collapsed folders of `spaceID` keep
    /// on screen, when they differ from what it last reported. Only the
    /// outermost collapsed folder on a path keeps rows: a folder inside it
    /// shows the way to the rows that folder keeps, not rows of its own.
    private func reportKeptRows(in spaceID: UUID) {
        guard let browser else { return }
        var kept: Set<UUID> = []
        if let space = browser.spaceModel(spaceID) {
            func keep(_ list: SidebarListModel, keeping folderKept: Set<UUID>) {
                for row in list.rows {
                    if row.kind.opensList {
                        keep(space.sidebar.inside(row.id), keeping: folderKept)
                    } else if !folderKept.isDisjoint(with: row.members) {
                        kept.formUnion(row.members)
                    }
                }
            }
            func walk(_ list: SidebarListModel) {
                for row in list.rows where row.kind.opensList {
                    guard space.folders.model(row.id)?.isCollapsed == true else {
                        walk(space.sidebar.inside(row.id))
                        continue
                    }
                    let assignment = BrowserFolderRuntimeAssignment(
                        folderID: row.id, spaceID: space.id, profileID: space.profileID)
                    guard let folderKept = collapsedFolders[assignment]?.state.keptTabIDs, !folderKept.isEmpty
                    else { continue }
                    keep(space.sidebar.inside(row.id), keeping: folderKept)
                }
            }
            walk(space.sidebar.section(.saved))
            walk(space.sidebar.section(.current))
        }
        guard reportedKeptRows[spaceID, default: []] != kept else { return }
        reportedKeptRows[spaceID] = kept
        browser.keepSidebarRows(in: spaceID, tabIDs: kept)
    }

    // MARK: - Actions - Delete hold

    /// Whether the delete control of the saved tab `tabID` is held back.
    func holdsDelete(of tabID: UUID) -> Bool {
        deleteHolds[tabID] != nil
    }

    /// Holds back the delete control of the saved tab `tabID` for `duration`,
    /// so the second click or tap of a double one on unload never deletes it.
    func holdDelete(of tabID: UUID, for duration: Duration) {
        let hold = UUID()
        deleteHolds[tabID] = hold
        Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard let self, self.deleteHolds[tabID] == hold else { return }
            self.deleteHolds[tabID] = nil
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
