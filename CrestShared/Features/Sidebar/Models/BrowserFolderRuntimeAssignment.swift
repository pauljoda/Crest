import Foundation

struct BrowserFolderRuntimeAssignment: Equatable, Hashable, Sendable {
    let folderID: FolderID
    let spaceID: SpaceID
    let profileID: UUID

    var spaceAssignment: BrowserSpaceRuntimeAssignment {
        BrowserSpaceRuntimeAssignment(
            spaceID: spaceID,
            profileID: profileID
        )
    }
}
