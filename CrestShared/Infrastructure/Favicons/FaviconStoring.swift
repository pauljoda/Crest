import Dispatch
import Foundation

/// Where a tab's favicon bytes live now that the session core does not carry
/// them.
///
/// Keyed by tab rather than by content hash. A hash key would dedupe icons shared
/// by tabs on one site, but it would also have to be written into the core blob
/// for the load-time join to find it — a new stored field on the tab record and
/// its sync payload. Keying by the tab that owns the icon keeps the tab record
/// untouched: the join already knows every tab ID, and
/// "which favicons are still referenced" is exactly "which live tabs still
/// exist", so there is no reference count to keep honest.
protocol BrowserFaviconStoring: AnyObject, Sendable {
    func favicon(tabID: UUID) -> Data?
    /// Updates one live tab's last known favicon. Missing or invalid bytes leave
    /// the cached file alone; pruning is the only operation that removes it.
    func reconcile(_ faviconData: Data?, tabID: UUID)
    /// Removes one live tab's favicon, which the core told it no longer to
    /// wear, so a later launch does not put it back.
    func forgetFavicon(tabID: UUID)
    /// The image one tab keeps for the page at its saved address, if any.
    func savedFavicon(tabID: UUID) -> BrowserSavedFavicon?
    /// Keeps `favicon` as one tab's saved page's image, or none when nil.
    func keepSavedFavicon(_ favicon: BrowserSavedFavicon?, tabID: UUID)
    /// Drops favicons, saved pages' included, for tabs the live session no
    /// longer has.
    func pruneFavicons(keeping tabIDs: Set<UUID>)
    func flushPendingWrites() async
}
