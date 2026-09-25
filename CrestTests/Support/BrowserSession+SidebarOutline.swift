import Foundation

@testable import Crest

extension BrowserSession {
    /// The rows the core's sidebar lists for this session's Space `spaceID`:
    /// the top level of `location`'s section, or the inside of `parentID`.
    /// The session opens in a window of its own, as a relaunch opens it.
    @MainActor
    func sidebarRows(
        in spaceID: SpaceID, location: BrowserFolderLocation, parentID: FolderID? = nil
    ) -> [SidebarRow] {
        let store = BrowserStore(session: self)
        guard let space = store.spaceModel(spaceID) else { return [] }
        let list = parentID.map { space.sidebar.inside($0) } ?? space.sidebar.section(location.tabPlacement)
        return list.rows
    }

    /// The identities of those rows, as the sidebar's reorder registry names
    /// them.
    @MainActor
    func sidebarRowIDs(
        in spaceID: SpaceID, location: BrowserFolderLocation, parentID: FolderID? = nil
    ) -> [BrowserSidebarReorderItemID] {
        sidebarRows(in: spaceID, location: location, parentID: parentID).map(BrowserSidebarReorderItemID.init)
    }
}

extension BrowserStore {
    /// The identities of the rows this window's core lists for the Space
    /// `spaceID`: the top level of `location`'s section, or the inside of
    /// `parentID`.
    func sidebarRowIDs(
        in spaceID: SpaceID, location: BrowserFolderLocation, parentID: FolderID? = nil
    ) -> [BrowserSidebarReorderItemID] {
        guard let space = spaceModel(spaceID) else { return [] }
        let list = parentID.map { space.sidebar.inside($0) } ?? space.sidebar.section(location.tabPlacement)
        return list.rows.map(BrowserSidebarReorderItemID.init)
    }
}
