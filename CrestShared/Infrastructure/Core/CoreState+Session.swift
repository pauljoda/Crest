import Foundation

/// Each session change updates the workspace it names and the images its tabs
/// wear. The images move first, while the read model still holds what the
/// change replaces, so a tab a change places anew is told apart from one it
/// keeps.
///
/// TRANSITIONAL until S6.7 deletes the Swift session copy: each change then
/// reaches the copy of its workspace, which registers here once its session
/// joins the device and reads its tabs' images from `favicons`.
extension CoreState {
    // MARK: - Types

    /// A registered session copy, held weakly: the family that owns it may go.
    struct SessionCopy {
        weak var authority: BrowserCoreSessionAuthority?
    }

    // MARK: - Actions - Registration

    /// Sends the changes of `workspace` to `authority`'s session copy.
    func register(_ authority: BrowserCoreSessionAuthority, for workspace: UUID) {
        sessionCopies = sessionCopies.filter { $0.value.authority != nil }
        sessionCopies[workspace] = SessionCopy(authority: authority)
    }

    /// The images the platform kept for the tabs of a workspace that opened
    /// before they were offered, as the persistent session a launch loads
    /// does: each tab the workspace holds that wears none takes its own.
    func adoptImages(_ images: [UUID: Data], in workspaceID: UUID) {
        guard let workspace = workspaces[workspaceID] else { return }
        let held = Set(workspace.tabIDs)
        favicons.adopt(images) { held.contains($0) }
    }

    // MARK: - Actions - Batches

    /// A batch of changes was applied: images of tabs a change removed and no
    /// workspace holds any longer are gone. In debug builds the read model is
    /// then checked against each session copy.
    func finishBatch(_ changes: [Change]) {
        favicons.finishBatch { tabID in workspaces.values.contains { $0.holds(tabID: tabID) } }
        #if DEBUG
            checkSessionCopies(after: changes)
        #endif
    }

    // MARK: - Actions - Changes

    func apply(_ change: WorkspaceOpened) {
        if let workspace = workspaces[change.workspaceID] {
            favicons.detach(workspace.tabIDs)
            favicons.place(change.session.spaces.flatMap(Self.tabIDs), in: change.workspaceID)
            workspace.apply(change)
        } else {
            favicons.place(change.session.spaces.flatMap(Self.tabIDs), in: change.workspaceID)
            workspaces[change.workspaceID] = WorkspaceModel(change)
        }
        forward(.workspaceOpened(change), to: change.workspaceID)
    }

    func apply(_ change: WorkspaceClosed) {
        if let workspace = workspaces.removeValue(forKey: change.workspaceID) { favicons.detach(workspace.tabIDs) }
        forward(.workspaceClosed(change), to: change.workspaceID)
        sessionCopies[change.workspaceID] = nil
    }

    func apply(_ change: WorkspaceChanged) {
        workspaces[change.workspaceID]?.apply(change)
        forward(.workspaceChanged(change), to: change.workspaceID)
    }

    func apply(_ change: AppPreferencesChanged) {
        workspaces[change.workspaceID]?.apply(change)
        forward(.appPreferencesChanged(change), to: change.workspaceID)
    }

    func apply(_ change: SpacesChanged) {
        if let workspace = workspaces[change.workspaceID] {
            for spaceID in change.removed { favicons.detach(workspace.spaces.model(spaceID)?.tabIDs ?? []) }
            favicons.place(change.added.flatMap(Self.tabIDs), in: change.workspaceID)
            workspace.apply(change)
        }
        forward(.spacesChanged(change), to: change.workspaceID)
    }

    func apply(_ change: SpaceSettingsChanged) {
        space(change.spaceID, in: change.workspaceID)?.apply(change)
        forward(.spaceSettingsChanged(change), to: change.workspaceID)
    }

    func apply(_ change: TabsChanged) {
        if let space = space(change.spaceID, in: change.workspaceID) {
            let gone = Set(change.removed)
            favicons.detach(change.removed)
            favicons.place(
                change.updated.map(\.id).filter { !space.tabs.contains($0) || gone.contains($0) },
                in: change.workspaceID)
            space.apply(change)
        }
        forward(.tabsChanged(change), to: change.workspaceID)
    }

    func apply(_ change: FoldersChanged) {
        space(change.spaceID, in: change.workspaceID)?.apply(change)
        forward(.foldersChanged(change), to: change.workspaceID)
    }

    func apply(_ change: SplitGroupsChanged) {
        space(change.spaceID, in: change.workspaceID)?.apply(change)
        forward(.splitGroupsChanged(change), to: change.workspaceID)
    }

    func apply(_ change: HistoryChanged) {
        space(change.spaceID, in: change.workspaceID)?.apply(change)
        forward(.historyChanged(change), to: change.workspaceID)
    }

    func apply(_ change: ArchiveChanged) {
        if let space = space(change.spaceID, in: change.workspaceID) {
            let gone = Set(change.removed)
            favicons.detach(change.removed)
            favicons.place(
                change.archived.map(\.tab.id).filter { !space.archive.contains(tabID: $0) || gone.contains($0) },
                in: change.workspaceID)
            space.apply(change)
        }
        forward(.archiveChanged(change), to: change.workspaceID)
    }

    func apply(_ change: TabCopied) {
        if workspaces[change.workspaceID]?.holdsOpen(tabID: change.copyTabID) == true {
            favicons.copy(change.sourceTabID, to: change.copyTabID, in: change.workspaceID)
        }
        forward(.tabCopied(change), to: change.workspaceID)
    }

    func apply(_ change: TabFaviconAssigned) {
        if workspaces[change.workspaceID]?.holdsOpen(tabID: change.tabID) == true {
            favicons.assign(adopts: change.adopts, to: change.tabID, in: change.workspaceID)
        }
        forward(.tabFaviconAssigned(change), to: change.workspaceID)
    }

    private func space(_ spaceID: UUID, in workspaceID: UUID) -> SpaceModel? {
        workspaces[workspaceID]?.spaces.model(spaceID)
    }

    /// Every tab a Space holds, open or archived.
    private static func tabIDs(of space: SpaceState) -> [UUID] {
        space.tabs.map(\.id) + space.archivedTabs.map(\.tab.id)
    }

    private func forward(_ change: Change, to workspace: UUID) {
        sessionCopies[workspace]?.authority?.receive(change, images: favicons)
    }
}
