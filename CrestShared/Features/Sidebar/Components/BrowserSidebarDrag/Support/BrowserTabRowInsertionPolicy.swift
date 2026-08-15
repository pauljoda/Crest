import CoreGraphics

enum BrowserTabRowInsertionPolicy {
    static func location(
        y: CGFloat,
        rowHeight: CGFloat,
        before: BrowserTabDropLocation,
        after: BrowserTabDropLocation
    ) -> BrowserTabDropLocation {
        guard rowHeight > 0 else { return before }
        return y < rowHeight / 2 ? before : after
    }

    static func followingTabID(
        after tabID: TabID,
        in tabs: [BrowserTab]
    ) -> TabID? {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else {
            return nil
        }
        let followingIndex = tabs.index(after: index)
        guard followingIndex < tabs.endIndex else { return nil }
        return tabs[followingIndex].id
    }

    static func followingTabIDs(in tabs: [BrowserTab]) -> [TabID: TabID] {
        Dictionary(
            uniqueKeysWithValues: zip(tabs, tabs.dropFirst()).map {
                ($0.id, $1.id)
            }
        )
    }
}
