import Foundation

@testable import Crest

/// What a window shows, as values read from `snapshot`, for tests.
extension BrowserStore {
    /// The Space this window shows, as `snapshot` holds it.
    var shownSpaceState: SpaceState? {
        snapshot.space(id: window.shownSpaceID)
    }

    /// The tab this window shows in the Space it shows, as `snapshot` holds it.
    var shownTabState: TabState? {
        guard let space = shownSpaceState, let tabID = window.shownTabID(in: space.id) else { return nil }
        return space.tabs.first { $0.id == tabID }
    }
}
