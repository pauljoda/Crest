import Foundation

extension BrowserSession {
    @discardableResult
    mutating func closeDurableTab(
        _ tabID: TabID,
        in spaceID: SpaceID,
        fallbackTabID: TabID?,
        returningToSavedURL: Bool
    ) -> Bool {
        #if CREST_CORE_BACKED
        return applyCoreEdit("tab.close_durable", in: spaceID, arguments: [
            "tabId": tabID.rawValue.uuidString,
            "fallbackTabId": fallbackTabID.map { $0.rawValue.uuidString as Any } ?? NSNull(),
            "returnToSavedURL": returningToSavedURL,
        ], at: .now) != nil
        #else
        guard let spaceIndex = spaces.firstIndex(where: { $0.id == spaceID }),
            let tabIndex = spaces[spaceIndex].tabs.firstIndex(where: {
                $0.id == tabID && $0.placement != .current
            })
        else { return false }
        if returningToSavedURL, let root = spaces[spaceIndex].tabs[tabIndex].savedSiteURL {
            spaces[spaceIndex].tabs[tabIndex].url = root
        }
        if spaces[spaceIndex].selectedTabID == tabID {
            spaces[spaceIndex].selectedTabID = fallbackTabID.flatMap {
                $0 != tabID && spaces[spaceIndex].contains($0) ? $0 : nil
            }
        }
        return true
        #endif
    }
}
