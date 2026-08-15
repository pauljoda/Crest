import Foundation

struct BrowserBookmarkDraft: Equatable, Sendable {
    let title: String
    let url: URL
    let folderID: UUID?
    let addedAt: Date
}
