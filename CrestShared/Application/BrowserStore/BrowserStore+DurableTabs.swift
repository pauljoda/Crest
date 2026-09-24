import Foundation

extension BrowserStore {
    /// Records an explicit close without removing the durable tab or archiving it.
    /// The page owner retires its runtime before publishing this session change.
    @discardableResult
    func closeDurableTab(
        _ assignment: BrowserTabRuntimeAssignment,
        returningToSavedURL: Bool
    ) -> Bool {
        let spaceAssignment = BrowserSpaceRuntimeAssignment(
            spaceID: assignment.spaceID, profileID: assignment.profileID
        )
        guard let space = space(matching: spaceAssignment),
            let tab = space.tabs.first(where: { $0.id == assignment.tabID }),
            tab.placement != .current
        else { return false }
        // Selecting another member would immediately present the just-closed
        // card again. Leave that split intact for the next explicit selection.
        let availableIDs = Set(
            space.tabs.filter {
                $0.id != tab.id && (tab.splitGroupID == nil || $0.splitGroupID != tab.splitGroupID)
            }.map(\.id))
        let fallbackID = tabSelectionHistory.fallbackTabID(
            afterDismissing: tab.id, in: space.id, availableTabIDs: availableIDs
        )
        let arguments = BrowserSessionArguments.TabCloseDurable(
            tabId: tab.id.rawValue, fallbackTabId: fallbackID?.rawValue, returnToSavedURL: returningToSavedURL)
        guard family.execute(.tabCloseDurable, in: space.id, arguments: arguments, from: self, at: .now) != nil
        else { return false }
        stageSync()
        return true
    }
}
