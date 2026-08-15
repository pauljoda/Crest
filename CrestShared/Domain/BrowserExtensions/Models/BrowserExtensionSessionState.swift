import Foundation

struct BrowserExtensionSessionState: Equatable, Sendable {
    let selectedSpaceID: SpaceID
    let spaces: [BrowserExtensionSpaceState]

    init(
        selectedSpaceID: SpaceID,
        spaces: [BrowserExtensionSpaceState]
    ) {
        self.selectedSpaceID = selectedSpaceID
        self.spaces = spaces
    }

    /// Projects a session for extensions. `runtimeActivity` supplies the live
    /// page state the session itself cannot carry, so a caller without resident
    /// pages still gets a well-formed snapshot.
    init(
        session: BrowserSession,
        runtimeActivity: (SpaceID, TabID) -> BrowserExtensionTabRuntimeActivity = {
            _, _ in .settled
        }
    ) {
        self.init(
            selectedSpaceID: session.selectedSpaceID,
            spaces: session.spaces.map { space in
                BrowserExtensionSpaceState(
                    id: space.id,
                    tabs: space.tabs.enumerated().map { index, tab in
                        let activity = runtimeActivity(space.id, tab.id)
                        return BrowserExtensionTabState(
                            id: tab.id,
                            title: tab.title,
                            url: tab.url,
                            placement: tab.placement,
                            index: index,
                            isSelected: tab.id == space.selectedTabID,
                            isLoadingComplete: activity.isLoadingComplete,
                            isReaderModeActive: activity.isReaderModeActive
                        )
                    }
                )
            }
        )
    }

    func space(_ id: SpaceID) -> BrowserExtensionSpaceState? {
        spaces.first { $0.id == id }
    }
}
