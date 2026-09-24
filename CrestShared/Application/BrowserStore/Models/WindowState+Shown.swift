import Foundation

/// What a window shows, in the identities the browser uses. The core owns it;
/// these only read it.
extension WindowState {
    var shownSpace: SpaceID { SpaceID(rawValue: shownSpaceID) }

    /// The tab the window shows in a Space, or nil when it shows none there.
    func shownTabID(in spaceID: SpaceID) -> TabID? {
        shownTabs.first { $0.spaceID == spaceID.rawValue }?.tabID.map(TabID.init(rawValue:))
    }

    /// The column shares the window keeps for a split group it resized.
    func splitColumnFractions(for groupID: SplitGroupID) -> [Double]? {
        splitColumnShares.first { $0.groupID == groupID.rawValue }?.shares
    }

    /// A window that shows `spaceID`, on `tabs` in the Spaces they name, for a
    /// preview no core window backs.
    static func preview(showing spaceID: SpaceID, tabs: [SpaceID: TabID] = [:]) -> WindowState {
        WindowState(
            id: UUID(), workspaceID: UUID(), shownSpaceID: spaceID.rawValue,
            shownTabs: tabs.map { ShownTab(spaceID: $0.key.rawValue, tabID: $0.value.rawValue) },
            splitColumnShares: [])
    }
}
