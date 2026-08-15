import CoreTransferable
import Foundation
import UniformTypeIdentifiers

struct BrowserTabDragItem: Codable, Equatable, Transferable, Sendable {
    let tabID: TabID
    let spaceID: SpaceID
    let profileID: UUID

    var runtimeAssignment: BrowserTabRuntimeAssignment {
        BrowserTabRuntimeAssignment(
            tabID: tabID,
            spaceID: spaceID,
            profileID: profileID
        )
    }

    var spaceAssignment: BrowserSpaceRuntimeAssignment {
        BrowserSpaceRuntimeAssignment(
            spaceID: spaceID,
            profileID: profileID
        )
    }

    static var transferRepresentation: some TransferRepresentation {
        // This payload never leaves Crest. JSON avoids advertising a document
        // type for an internal sidebar-reordering gesture.
        CodableRepresentation(contentType: .json)
    }
}
