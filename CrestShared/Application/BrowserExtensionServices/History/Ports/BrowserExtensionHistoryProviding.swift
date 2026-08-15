import Foundation

/// The port backing Crest's emulated `chrome.history` and `chrome.topSites`
/// namespaces.
///
/// Every entry point is scoped by ``BrowserSpaceRuntimeAssignment`` rather than
/// by a bare `SpaceID`, because that is how Crest's own history mutations are
/// scoped: history lives inside each `BrowserSpace`, and a request captured
/// against a Space that has since been replaced or deleted must not reach its
/// successor's data. A scope that no longer resolves yields empty reads and
/// `false` writes rather than falling back to the selected Space.
///
/// Two Chrome fields have no counterpart in Crest's storage and are documented
/// where they appear: `typedCount` is always zero, and `getVisits` reports only
/// the first and last visit because Crest keeps one row per URL rather than one
/// row per visit.
@MainActor
protocol BrowserExtensionHistoryProviding: AnyObject {
    /// Backs `chrome.history.search`. Results are most-recent-first.
    func search(
        _ query: BrowserExtensionHistoryQuery,
        in scope: BrowserSpaceRuntimeAssignment
    ) -> [BrowserExtensionHistoryItem]

    /// Backs `chrome.history.getVisits`, oldest visit first.
    func visits(
        for url: URL,
        in scope: BrowserSpaceRuntimeAssignment
    ) -> [BrowserExtensionHistoryVisit]

    /// Backs `chrome.history.addUrl`, recording a visit at the current time.
    @discardableResult
    func addURL(
        _ url: URL,
        title: String?,
        in scope: BrowserSpaceRuntimeAssignment
    ) -> Bool

    /// Backs `chrome.history.deleteUrl`.
    @discardableResult
    func deleteURL(
        _ url: URL,
        in scope: BrowserSpaceRuntimeAssignment
    ) -> Bool

    /// Backs `chrome.history.deleteRange` over the half-open window
    /// `startDate ..< endDate`.
    @discardableResult
    func deleteRange(
        from startDate: Date,
        until endDate: Date,
        in scope: BrowserSpaceRuntimeAssignment
    ) -> Bool

    /// Backs `chrome.history.deleteAll`, scoped to one Space.
    @discardableResult
    func deleteAll(in scope: BrowserSpaceRuntimeAssignment) -> Bool

    /// Backs `chrome.topSites.get`, ranked by ``BrowserExtensionTopSitePolicy``.
    func topSites(
        limit: Int,
        in scope: BrowserSpaceRuntimeAssignment
    ) -> [BrowserExtensionTopSite]

    /// Backs `chrome.history.onVisited` and `onVisitRemoved`.
    ///
    /// The stream finishes once `scope` stops resolving, so a deleted or
    /// replaced Space tears its observers down instead of going silent.
    func changes(
        in scope: BrowserSpaceRuntimeAssignment
    ) -> AsyncStream<BrowserExtensionHistoryChange>
}
