import CoreTransferable
import Foundation
import UniformTypeIdentifiers

struct BrowserDragSessionToken: Equatable, Sendable {
    let rawValue: UUID

    init(generation: UInt64) {
        let value = generation.bigEndian
        rawValue = withUnsafeBytes(of: value) { bytes in
            UUID(
                uuid: (
                    0x43, 0x52, 0x45, 0x53, 0x54, 0x44, 0x52, 0x41,
                    bytes[0], bytes[1], bytes[2], bytes[3],
                    bytes[4], bytes[5], bytes[6], bytes[7]
                )
            )
        }
    }
}

enum BrowserTabDragSessionLifecyclePhase: Equatable, Sendable {
    case active
    case ended
    case dataTransferCompleted
}

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
