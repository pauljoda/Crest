import Foundation

struct BrowserTabSessionTabDraft: Equatable, Sendable {
    let title: String
    let url: URL
    let placement: TabPlacement
    let folderSourceID: String?
    let lastActivatedAt: Date

    init(
        title: String,
        url: URL,
        isPinned: Bool,
        lastActivatedAt: Date
    ) {
        self.title = title
        self.url = url
        placement = isPinned ? .pinned : .current
        folderSourceID = nil
        self.lastActivatedAt = lastActivatedAt
    }

    init(
        title: String,
        url: URL,
        placement: TabPlacement,
        folderSourceID: String? = nil,
        lastActivatedAt: Date
    ) {
        self.title = title
        self.url = url
        self.placement = placement
        self.folderSourceID = placement == .saved ? folderSourceID : nil
        self.lastActivatedAt = lastActivatedAt
    }
}
