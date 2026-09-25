import Foundation

extension CoreState {
    /// The journal changed. A stage reached it, so the last failure no longer
    /// stands. Its workspace's family hears of it, so a cleanup a merge that
    /// changed nothing else owes runs again.
    func apply(_ change: SyncJournalChanged) {
        syncJournal = change
        syncStagingFailure = nil
        touchedWorkspaces.insert(change.workspaceID)
    }

    func apply(_ change: SyncStagingFailed) {
        syncStagingFailure = change.reason
    }
}
