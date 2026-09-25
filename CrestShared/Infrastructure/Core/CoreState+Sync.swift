import Foundation

extension CoreState {
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
