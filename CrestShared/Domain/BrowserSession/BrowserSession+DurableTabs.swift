import Foundation

extension BrowserSession {
    @discardableResult
    mutating func closeDurableTab(
        _ tabID: TabID,
        in spaceID: SpaceID,
        fallbackTabID: TabID?,
        returningToSavedURL: Bool
    ) -> Bool {
        return applyCoreEdit("tab.close_durable", in: spaceID, arguments: [
            "tabId": tabID.rawValue.uuidString,
            "fallbackTabId": fallbackTabID.map { $0.rawValue.uuidString as Any } ?? NSNull(),
            "returnToSavedURL": returningToSavedURL,
        ], at: .now) != nil
    }
}
