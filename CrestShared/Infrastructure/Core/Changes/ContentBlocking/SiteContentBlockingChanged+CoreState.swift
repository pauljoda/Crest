import Foundation

extension SiteContentBlockingChanged {
    @MainActor func apply(to state: CoreState) {
        state.blockingSites = sites
    }
}
