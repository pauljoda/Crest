import Foundation

extension CoreState {
    /// A stage reached the journal, so the last failure no longer stands.
    func apply(_ change: SyncJournalChanged) {
        syncStagingFailure = nil
    }

    func apply(_ change: SyncStagingFailed) {
        syncStagingFailure = change.reason
    }
}
