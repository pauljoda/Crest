/// What one window renders: the core's browsing data together with that
/// window's own selection. It is a presentation value built by `BrowserStore`
/// for views and page pools; it is not Codable, never sent to the core and never
/// stored, so selection stays window state.
struct BrowserPresentedSession: Equatable {
    // MARK: - Variables

    let session: BrowserSession
    let selection: BrowserStoreSelection

    var spaces: [BrowserSpace] { session.spaces }
    var defaultSpaceID: SpaceID? { session.defaultSpaceID }
    var selectedSpaceID: SpaceID { selection.selectedSpaceID }
    /// Nil while the shown Space is being deleted.
    var selectedSpace: BrowserSpace? {
        guard session.spaceDeletions?.contains(where: { $0.spaceID == selectedSpaceID }) != true else { return nil }
        return selection.selectedSpace(in: session)
    }
    var selectedTab: BrowserTab? {
        guard selectedSpace != nil else { return nil }
        return selection.selectedTab(in: session)
    }
    var tabIDs: [TabID] { session.tabIDs }
    var tabRuntimeAssignments: Set<BrowserTabRuntimeAssignment> { session.tabRuntimeAssignments }

    // MARK: - Actions - Queries

    /// The tab this window shows in a Space, if any.
    func selectedTabID(in spaceID: SpaceID) -> TabID? {
        selection.selectedTabID(in: spaceID)
    }

    func space(id: SpaceID) -> BrowserSpace? {
        session.space(id: id)
    }

    func spaceID(containing tabID: TabID) -> SpaceID? {
        session.spaceID(containing: tabID)
    }
}
