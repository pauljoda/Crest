import Foundation

struct BrowserFolderNode: Equatable, Identifiable, Sendable {
    let folder: BrowserFolder
    let depth: Int
    let hasChildren: Bool

    var id: FolderID { folder.id }
}
