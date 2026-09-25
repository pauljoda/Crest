import Foundation

extension CoreState {
    // MARK: - Variables

    /// Whether the session whose journal syncs is still the disposable seed a
    /// first launch made, which the cloud's content replaces before anything
    /// syncs.
    var syncsDisposableSeed: Bool {
        guard let journal = syncJournal else { return false }
        return workspaces[journal.workspaceID]?.isDisposableSeed == true
    }

    // MARK: - Actions - Changes

    /// The journal changed. A stage reached it, so the last failure no longer
    /// stands.
    func apply(_ change: SyncJournalChanged) {
        syncJournal = change
        syncStagingFailure = nil
    }

    func apply(_ change: SyncStagingFailed) {
        syncStagingFailure = change.reason
    }
}
