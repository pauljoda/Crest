import Foundation

/// Split-level link operations a page needs from whatever owns its tabs. Both
/// are synchronous because AppKit is building a context menu on the main thread
/// when it asks, and a menu cannot wait for an answer.
@MainActor
struct BrowserSplitLinkHost {
    var canOpenLink: (TabID, BrowserSpaceRuntimeAssignment) -> Bool
    var openLink: (URL, TabID, BrowserSpaceRuntimeAssignment) -> Void

    init(
        canOpenLink: @escaping (TabID, BrowserSpaceRuntimeAssignment) -> Bool,
        openLink: @escaping (URL, TabID, BrowserSpaceRuntimeAssignment) -> Void
    ) {
        self.canOpenLink = canOpenLink
        self.openLink = openLink
    }

    /// Offers no split at all. Pools built without a store (tests, previews)
    /// simply leave the menu item out.
    static let unavailable = BrowserSplitLinkHost(
        canOpenLink: { _, _ in false },
        openLink: { _, _, _ in }
    )
}
