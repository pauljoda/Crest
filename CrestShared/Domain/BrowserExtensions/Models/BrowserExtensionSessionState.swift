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

struct BrowserExtensionSpaceState: Equatable, Sendable {
    let id: SpaceID
    let tabs: [BrowserExtensionTabState]

    var selectedTabID: TabID? {
        tabs.first(where: \.isSelected)?.id
    }

    func tab(_ id: TabID) -> BrowserExtensionTabState? {
        tabs.first { $0.id == id }
    }
}

/// Live page state a `BrowserSession` cannot carry, resolved per tab while a
/// session snapshot is projected for extensions. A tab with no resident page
/// reports the settled values.
struct BrowserExtensionTabRuntimeActivity: Equatable, Sendable {
    static let settled = BrowserExtensionTabRuntimeActivity()

    let isLoadingComplete: Bool
    let isReaderModeActive: Bool

    init(
        isLoadingComplete: Bool = true,
        isReaderModeActive: Bool = false
    ) {
        self.isLoadingComplete = isLoadingComplete
        self.isReaderModeActive = isReaderModeActive
    }
}

struct BrowserExtensionTabState: Equatable, Sendable {
    let id: TabID
    let title: String
    let url: URL?
    let placement: TabPlacement
    let index: Int
    let isSelected: Bool
    /// Whether the tab's page has finished loading. Runtime-only state that no
    /// persisted session carries, so a projection built without a live page
    /// reports a settled tab rather than inventing a load.
    let isLoadingComplete: Bool
    /// Whether the tab is currently presenting Crest's reader mode. Runtime-only
    /// for the same reason as `isLoadingComplete`.
    let isReaderModeActive: Bool

    init(
        id: TabID,
        title: String,
        url: URL?,
        placement: TabPlacement,
        index: Int,
        isSelected: Bool,
        isLoadingComplete: Bool = true,
        isReaderModeActive: Bool = false
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.placement = placement
        self.index = index
        self.isSelected = isSelected
        self.isLoadingComplete = isLoadingComplete
        self.isReaderModeActive = isReaderModeActive
    }
}

/// A page extensions can see and address that the browsing session does not
/// carry as a tab.
///
/// A Peek is the case this exists for. It is a real document in a Space,
/// created with that Space's extension controller attached, so WebKit injects
/// every granted content script into it. WebKit answers a content script's
/// `runtime` messages by mapping its web view back to a tab the host has
/// announced, so a page that is never announced leaves those scripts talking to
/// nobody: their opening question is rejected outright, and an extension that
/// styles pages keeps whatever partial state it applied before asking. The page
/// stays wrong until it is reloaded.
///
/// Announcing the page is what makes WebKit's two halves agree. It is also the
/// truthful description: the person is looking at a live page, so hiding it
/// from extensions while still running their code inside it is the dishonest
/// half of the current arrangement, not the disclosure.
struct BrowserExtensionTransientTab: Equatable, Sendable {
    let id: TabID
    let url: URL
}
