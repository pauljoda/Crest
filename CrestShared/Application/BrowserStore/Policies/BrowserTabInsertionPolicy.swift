import Foundation

enum BrowserTabInsertionPolicy {
    static func requestedIndex(
        after originTabID: TabID?,
        in space: BrowserSpace
    ) -> Int? {
        guard let originTabID,
              let originIndex = space.tabs.firstIndex(where: { $0.id == originTabID }) else {
            return nil
        }
        return space.tabs.index(after: originIndex)
    }
}
