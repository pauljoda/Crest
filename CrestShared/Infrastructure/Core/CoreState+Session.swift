import Foundation

/// TRANSITIONAL until S6.1 gives the read model the session itself: each
/// session change reaches the Swift session copy of the workspace it names,
/// which registers here once its session joins the device. Changes for a
/// workspace no copy registered for are dropped.
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

    /// A batch of changes was applied: images a change removed and no later
    /// change placed again are gone.
    func sessionBatchApplied() {
        detachedImages.removeAll()
    }

    // MARK: - Actions - Changes

    func apply(_ change: WorkspaceOpened) { forward(.workspaceOpened(change), to: change.workspaceID) }

    func apply(_ change: WorkspaceClosed) {
        forward(.workspaceClosed(change), to: change.workspaceID)
        sessionCopies[change.workspaceID] = nil
    }

    func apply(_ change: WorkspaceChanged) { forward(.workspaceChanged(change), to: change.workspaceID) }

    func apply(_ change: AppPreferencesChanged) { forward(.appPreferencesChanged(change), to: change.workspaceID) }

    func apply(_ change: SpacesChanged) { forward(.spacesChanged(change), to: change.workspaceID) }

    func apply(_ change: SpaceSettingsChanged) { forward(.spaceSettingsChanged(change), to: change.workspaceID) }

    func apply(_ change: TabsChanged) { forward(.tabsChanged(change), to: change.workspaceID) }

    func apply(_ change: FoldersChanged) { forward(.foldersChanged(change), to: change.workspaceID) }

    func apply(_ change: SplitGroupsChanged) { forward(.splitGroupsChanged(change), to: change.workspaceID) }

    func apply(_ change: HistoryChanged) { forward(.historyChanged(change), to: change.workspaceID) }

    func apply(_ change: ArchiveChanged) { forward(.archiveChanged(change), to: change.workspaceID) }

    func apply(_ change: TabCopied) { forward(.tabCopied(change), to: change.workspaceID) }

    func apply(_ change: TabFaviconAssigned) { forward(.tabFaviconAssigned(change), to: change.workspaceID) }

    private func forward(_ change: Change, to workspace: UUID) {
        sessionCopies[workspace]?.authority?.receive(change, detachedImages: &detachedImages)
    }
}
