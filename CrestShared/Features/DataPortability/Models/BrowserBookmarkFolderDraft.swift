import Foundation

struct BrowserBookmarkFolderDraft: Equatable, Sendable {
    let id: UUID
    let title: String
    let parentID: UUID?
}
