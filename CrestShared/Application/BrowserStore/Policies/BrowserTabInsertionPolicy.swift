import Foundation

enum BrowserTabInsertionPolicy {
    static func requestedIndex(
        after originTabID: TabID?,
        in space: BrowserSpace
    ) -> Int? {
        guard let originTabID,
            let originIndex = space.tabs.firstIndex(where: { $0.id == originTabID })
        else {
            return nil
        }
        guard let groupID = space.splitGroup(containing: originTabID) else {
            return space.tabs.index(after: originIndex)
        }

        var insertionIndex = space.tabs.index(after: originIndex)
        while insertionIndex < space.tabs.endIndex,
            space.tabs[insertionIndex].splitGroupID == groupID
        {
            insertionIndex = space.tabs.index(after: insertionIndex)
        }
        return insertionIndex
    }
}
