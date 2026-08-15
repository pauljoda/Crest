import CoreTransferable
import UniformTypeIdentifiers

struct BrowserFolderDragItem: Codable, Equatable, Transferable, Sendable {
    let folderID: FolderID
    let spaceID: SpaceID
    let profileID: UUID

    var spaceAssignment: BrowserSpaceRuntimeAssignment {
        BrowserSpaceRuntimeAssignment(
            spaceID: spaceID,
            profileID: profileID
        )
    }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }
}
