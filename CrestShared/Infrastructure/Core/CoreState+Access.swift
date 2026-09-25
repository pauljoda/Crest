import Foundation

extension CoreState {
    /// A Space profile that holds no grant and waits on nobody leaves the map.
    func apply(_ change: SpaceLockChanged) {
        var access = spaceAccessStorage
        let assignment = BrowserSpaceRuntimeAssignment(
            spaceID: change.spaceID, profileID: change.profileID)
        access[assignment] = change.isUnlocked || change.isAuthenticating ? change : nil
        publish(access, into: \.spaceAccessStorage, as: \.spaceAccess)
    }
}
