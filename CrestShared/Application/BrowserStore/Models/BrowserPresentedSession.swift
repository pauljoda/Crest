/// What one window renders: the core's browsing data together with what the
/// core says that window shows. It is a presentation value built by
/// `BrowserStore` for views and page pools; it is not Codable and never
/// stored, so what a window shows stays the core's window state.
struct BrowserPresentedSession: Equatable {
    // MARK: - Variables

    let session: BrowserSession
    let window: WindowState

    var spaces: [BrowserSpace] { session.spaces }
    var defaultSpaceID: SpaceID? { session.defaultSpaceID }
    var selectedSpaceID: SpaceID { window.shownSpace }
    /// Nil while the shown Space is being deleted.
    var selectedSpace: BrowserSpace? {
        guard session.spaceDeletions?.contains(where: { $0.spaceID == selectedSpaceID }) != true else { return nil }
        return session.space(id: selectedSpaceID)
    }
    var selectedTab: BrowserTab? {
        guard let space = selectedSpace, let tabID = window.shownTabID(in: space.id) else { return nil }
        return space.tabs.first { $0.id == tabID }
    }
    var tabIDs: [TabID] { session.tabIDs }
    var tabRuntimeAssignments: Set<BrowserTabRuntimeAssignment> { session.tabRuntimeAssignments }

    // MARK: - Actions - Queries

    /// The tab this window shows in a Space, if any.
    func selectedTabID(in spaceID: SpaceID) -> TabID? {
        window.shownTabID(in: spaceID)
    }

    func space(id: SpaceID) -> BrowserSpace? {
        session.space(id: id)
    }

    func spaceID(containing tabID: TabID) -> SpaceID? {
        session.spaceID(containing: tabID)
    }
}
