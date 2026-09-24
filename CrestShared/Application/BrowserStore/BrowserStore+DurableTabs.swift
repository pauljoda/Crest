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
        // The core returns the window to the tab it showed before, skipping the
        // closed tab's split, whose other members would present it again.
        let arguments = BrowserSessionArguments.TabCloseDurable(
            tabId: tab.id.rawValue, returnToSavedURL: returningToSavedURL)
        guard family.execute(.tabCloseDurable, in: space.id, arguments: arguments, from: self, at: .now) != nil
        else { return false }
        stageSync()
        return true
    }
}
