import Foundation

struct BrowserFolderNode: Equatable, Identifiable, Sendable {
    let folder: SavedFolder
    let depth: Int
    let hasChildren: Bool

    var id: FolderID { folder.id }
}
