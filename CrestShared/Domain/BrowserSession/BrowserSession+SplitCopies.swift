import Foundation

extension BrowserSession {
    /// Prepares the entire join in a value copy. A refused intent publishes no
    /// tabs, selection changes, or partially copied groups.
    mutating func addTabToSplitPreservingDurableTabs(
        _ tabID: TabID,
        joining targetTabID: TabID,
        at memberIndex: Int?,
        in spaceID: SpaceID,
        at date: Date = .now
    ) -> [(source: TabID, copy: TabID)]? {
        guard spaceID == selectedSpaceID,
            let result = applyCoreEdit("split.join", in: spaceID, arguments: [
                "tabId": tabID.rawValue.uuidString, "targetId": targetTabID.rawValue.uuidString,
                "index": memberIndex as Any? ?? NSNull(), "ids": (0..<6).map { _ in UUID().uuidString }
            ], at: date)
        else { return nil }
        return result.copies.map { (source: TabID(rawValue: $0.source), copy: TabID(rawValue: $0.copy)) }
    }
}
