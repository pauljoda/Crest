import Foundation

enum BrowserCoreTabTransfer {
    // MARK: - Types

    struct Result: Decodable {
        var source: BrowserSpace
        var destination: BrowserSpace
    }

    /// Where a moved tab lands, and whether the window that moved it follows.
    struct Arguments: Encodable, Sendable {
        let tabId: UUID
        @BrowserCoreNullable var placement: TabPlacement?
        @BrowserCoreNullable var folderId: UUID?
        @BrowserCoreNullable var before: UUID?
        let select: Bool

        init(
            tabID: TabID, placement: TabPlacement? = nil, folderID: FolderID? = nil,
            before: TabID? = nil, selecting: Bool = false
        ) {
            tabId = tabID.rawValue
            self.placement = placement
            folderId = folderID?.rawValue
            self.before = before?.rawValue
            select = selecting
        }
    }

    // MARK: - Actions - Projection

    static func applying(_ edited: BrowserSpace, to session: BrowserSession, moved: BrowserTab) throws
        -> BrowserSession
    {
        guard let index = session.spaces.firstIndex(where: { $0.id == edited.id }),
            session.spaces[index].profile.id == edited.profile.id
        else { throw BrowserPortableArchiveError.invalidContents }
        let existing = session.spaces[index]
        var result = session
        var space = edited
        let images = Dictionary(uniqueKeysWithValues: existing.tabs.map { ($0.id, $0.faviconData) })
        space.tabs = space.tabs.map { tab in
            var value = tab
            value.faviconData = tab.id == moved.id ? moved.faviconData : images[tab.id] ?? nil
            return value
        }
        space.history = existing.history
        space.archivedTabs = existing.archivedTabs
        result.spaces[index] = space
        return result
    }
}
