import Foundation

struct BrowserDownloadRetryLease: Equatable, Sendable {
    let id: UUID
    let itemID: UUID
    let assignment: BrowserSpaceRuntimeAssignment

    init(
        id: UUID,
        itemID: UUID,
        profileID: UUID,
        spaceID: SpaceID
    ) {
        self.id = id
        self.itemID = itemID
        assignment = BrowserSpaceRuntimeAssignment(
            spaceID: spaceID,
            profileID: profileID
        )
    }
}
