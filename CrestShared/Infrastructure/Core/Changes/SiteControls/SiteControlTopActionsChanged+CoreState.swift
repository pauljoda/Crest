import Foundation

extension SiteControlTopActionsChanged {
    /// The core publishes the four whole.
    @MainActor func apply(to state: CoreState) {
        state.siteControlTopActions = topActions
    }
}
