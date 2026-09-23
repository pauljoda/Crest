import Foundation

enum BrowserCoreTabTransfer {
    struct Result: Decodable {
        var source: BrowserSpace
        var destination: BrowserSpace
        /// A move between two Spaces of one workspace answers its window once.
        var selection: BrowserSelectionHint?
        /// A move between workspaces answers each side's window.
        var sourceSelection: BrowserSelectionHint?
        var destinationSelection: BrowserSelectionHint?
    }
    static func arguments(tabID: TabID, placement: TabPlacement? = nil, folderID: FolderID? = nil,
        before: TabID? = nil, fallback: TabID? = nil, selecting: Bool = false) -> [String: Any] {
        ["tabId": tabID.rawValue.uuidString, "placement": placement?.rawValue as Any? ?? NSNull(),
            "folderId": folderID?.rawValue.uuidString as Any? ?? NSNull(),
            "before": before?.rawValue.uuidString as Any? ?? NSNull(),
            "fallbackTabId": fallback?.rawValue.uuidString as Any? ?? NSNull(), "select": selecting]
    }
    static func applying(_ edited: BrowserSpace, to session: BrowserSession, moved: BrowserTab) throws -> BrowserSession {
        guard let index = session.spaces.firstIndex(where: { $0.id == edited.id }),
            session.spaces[index].profile.id == edited.profile.id
        else { throw BrowserPortableArchiveError.invalidContents }
        let existing = session.spaces[index]
        var result = session; var space = edited
        let images = Dictionary(uniqueKeysWithValues: existing.tabs.map { ($0.id, $0.faviconData) })
        space.tabs = space.tabs.map { tab in
            var value = tab; value.faviconData = tab.id == moved.id ? moved.faviconData : images[tab.id] ?? nil; return value
        }
        space.history = existing.history; space.archivedTabs = existing.archivedTabs
        result.spaces[index] = space
        return result
    }
}
