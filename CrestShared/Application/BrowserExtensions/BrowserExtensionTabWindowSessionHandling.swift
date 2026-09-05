import Foundation

@MainActor
protocol BrowserExtensionTabWindowSessionHandling: AnyObject {
    var session: BrowserSession { get }

    func moveExtensionTabs(_ ids: [TabID], in spaceID: SpaceID, to index: Int) -> Bool

    func activateExtensionTab(_ id: TabID, in spaceID: SpaceID) -> Bool
    func closeExtensionTab(_ id: TabID, in spaceID: SpaceID) -> Bool
    func loadExtensionURL(_ url: URL, in tabID: TabID, spaceID: SpaceID) -> Bool
    func setExtensionTabPinned(
        _ pinned: Bool,
        tabID: TabID,
        in spaceID: SpaceID
    ) -> Bool
    func openExtensionTab(
        url: URL?,
        in spaceID: SpaceID,
        pinned: Bool,
        requestedIndex: Int?,
        shouldSelect: Bool
    ) -> TabID?
    func duplicateExtensionTab(
        _ id: TabID,
        in spaceID: SpaceID,
        pinned: Bool,
        requestedIndex: Int?,
        shouldSelect: Bool
    ) -> TabID?
    func selectSpace(_ id: SpaceID)
}
