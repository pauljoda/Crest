import Foundation

extension SiteZoomChanged {
    /// The read model holds no site zoom: each page asks the core for its
    /// site's when it heads there, then follows these changes.
    @MainActor func apply(to state: CoreState) {}

    @MainActor func apply(to core: CrestCore, in batch: inout CoreChangeBatch) {
        batch.siteZoomChanges.append(self)
    }
}
