import Foundation

extension SiteZoomChanged {
    @MainActor func apply(to state: CoreState) {}

    @MainActor func apply(to core: CrestCore, in batch: inout CoreChangeBatch) {
        batch.siteZoomChanges.append(self)
    }
}
