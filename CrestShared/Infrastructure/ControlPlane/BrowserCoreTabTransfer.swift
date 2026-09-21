#if CREST_CORE_BACKED
import Foundation

enum BrowserCoreTabTransfer {
    struct Result: Decodable {
        var source: BrowserSpace
        var destination: BrowserSpace
    }
    static func arguments(tabID: TabID, placement: TabPlacement? = nil, folderID: FolderID? = nil,
        before: TabID? = nil, fallback: TabID? = nil, selecting: Bool = false) -> [String: Any] {
        ["tabId": tabID.rawValue.uuidString, "placement": placement?.rawValue as Any? ?? NSNull(),
            "folderId": folderID?.rawValue.uuidString as Any? ?? NSNull(),
            "before": before?.rawValue.uuidString as Any? ?? NSNull(),
            "fallbackTabId": fallback?.rawValue.uuidString as Any? ?? NSNull(), "select": selecting]
    }
    static func preview(source: BrowserSpace, destination: BrowserSpace,
        arguments: [String: Any], at date: Date) throws -> Result {
        func compact(_ space: BrowserSpace) throws -> Any {
            var value = space; value.history = []; value.archivedTabs = []
            value.tabs = value.tabs.map { var tab = $0; tab.faviconData = nil; return tab }
            return try BrowserCoreSync.value(value)
        }
        return try BrowserCoreSync.query(["version": 1, "operation": "transfer.preview",
            "source": compact(source), "destination": compact(destination), "arguments": arguments,
            "now": date.timeIntervalSinceReferenceDate])
    }
    static func applying(_ edited: BrowserSpace, to session: BrowserSession, moved: BrowserTab,
        selectingSpace: Bool = false) throws -> BrowserSession {
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
        if selectingSpace { result.selectedSpaceID = space.id }
        return result
    }
}
#endif
