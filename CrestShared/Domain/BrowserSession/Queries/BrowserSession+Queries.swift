import Foundation

extension BrowserSession {
    var hasDisposableSeedState: Bool {
        disposableSeedMarker != nil
    }

    var selectedSpace: BrowserSpace? {
        spaces.first { $0.id == selectedSpaceID }
    }

    var selectedTab: BrowserTab? {
        guard let space = selectedSpace, let selectedTabID = space.selectedTabID else { return nil }
        return space.tabs.first { $0.id == selectedTabID }
    }

    var tabIDs: [TabID] {
        spaces.flatMap { $0.tabs.map(\.id) }
    }

    var tabRuntimeAssignments: Set<BrowserTabRuntimeAssignment> {
        Set(
            spaces.flatMap { space in
                space.tabs.map { tab in
                    BrowserTabRuntimeAssignment(
                        tabID: tab.id,
                        spaceID: space.id,
                        profileID: space.profile.id
                    )
                }
            }
        )
    }

    func space(id: SpaceID) -> BrowserSpace? {
        spaces.first { $0.id == id }
    }

    func spaceID(containing tabID: TabID) -> SpaceID? {
        spaces.first(where: { $0.contains(tabID) })?.id
    }
}
