import Foundation

extension CoreState {
    func apply(_ change: Saved) {
        savedRevision = max(savedRevision, change.revision)
        storageFailure = nil
    }

    func apply(_ change: StorageFailed) {
        storageFailure = change.reason
    }
}
