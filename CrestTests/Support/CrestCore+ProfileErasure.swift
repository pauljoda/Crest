import Foundation
@testable import Crest

extension CrestCore {
    /// Has every engine erase each profile `deletion` erases, which keeps
    /// nothing on disk in a test, as the app's deleter does before the Space
    /// may go.
    func eraseProfiles(of deletion: SpaceDeletionState) async throws {
        for profileID in deletion.erasing {
            guard await deleteData(DeleteProfileData(requestID: UUID(), profileID: profileID, ephemeral: true))
            else { throw BrowserSpaceDeletionError.dataNotErased }
        }
    }
}

extension SpaceDeletionState {
    /// A deletion of `space`, a Space on its own, which erases its profile.
    static func erasing(_ space: SpaceState.Seed) -> SpaceDeletionState {
        SpaceDeletionState(
            id: UUID(), spaceID: space.id, profileID: space.ownProfileID, erasedProfileIDs: [space.profileID],
            successorID: nil, erasing: [space.profileID])
    }
}
