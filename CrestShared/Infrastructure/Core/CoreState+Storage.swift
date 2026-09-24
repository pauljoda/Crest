import Foundation

extension CoreState {
    func apply(_ change: Saved) {
        savedRevision = max(savedRevision, change.revision)
        storageFailure = nil
    }

    func apply(_ change: StorageFailed) {
        storageFailure = change.reason
    }

    /// The images an adopted session carried are native assets the launch
    /// stores; the read model keeps nothing of the adoption.
    func apply(_ change: SessionAdopted) {}
}
