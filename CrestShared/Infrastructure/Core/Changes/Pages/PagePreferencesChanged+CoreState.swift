import Foundation

extension PagePreferencesChanged {
    /// The core publishes the page preferences whole.
    @MainActor func apply(to state: CoreState) {
        state.pagePreferences = preferences
    }
}
