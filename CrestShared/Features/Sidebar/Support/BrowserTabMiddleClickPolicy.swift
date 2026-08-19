import Foundation

/// What an auxiliary click on a sidebar tab row asks for.
enum BrowserTabMiddleClickAction: Equatable {
    case close
    case unload
}

/// Reads that action off the row's placement.
///
/// A current tab is a session member, so dismissing it means closing it. A
/// pinned or saved tab outlives the session and only its page can be put away,
/// which makes the same gesture an unload rather than a delete.
enum BrowserTabMiddleClickPolicy {
    static func action(for placement: TabPlacement) -> BrowserTabMiddleClickAction {
        placement == .current ? .close : .unload
    }
}
