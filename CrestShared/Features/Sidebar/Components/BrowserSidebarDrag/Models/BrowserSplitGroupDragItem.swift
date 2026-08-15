import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// A split group lifted from the sidebar. The whole run travels as one block, so
/// the payload carries the group's identity plus the members it stood for when
/// the lift began — the commit re-reads the live run, and the captured IDs are
/// what let a guard notice the group changed under the drag.
///
/// `Transferable` for the same reason `BrowserTabDragItem` is: iOS lifts a row
/// through drag-and-drop, and a drag session needs something to carry. The
/// payload still never leaves Crest — nothing outside the sidebar's own drop
/// delegate reads it.
struct BrowserSplitGroupDragItem: Codable, Equatable, Transferable, Sendable {
    let groupID: SplitGroupID
    let spaceID: SpaceID
    let profileID: UUID
    let memberTabIDs: [TabID]

    var spaceAssignment: BrowserSpaceRuntimeAssignment {
        BrowserSpaceRuntimeAssignment(
            spaceID: spaceID,
            profileID: profileID
        )
    }

    static var transferRepresentation: some TransferRepresentation {
        // JSON avoids advertising a document type for an internal sidebar
        // reordering gesture, exactly as the tab payload does.
        CodableRepresentation(contentType: .json)
    }
}
