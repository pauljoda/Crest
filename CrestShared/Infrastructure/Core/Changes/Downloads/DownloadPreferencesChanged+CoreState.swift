import Foundation

extension DownloadPreferencesChanged {
    /// The core publishes every Space's download preferences whole.
    @MainActor func apply(to state: CoreState) {
        state.downloadPreferences = spaces
    }
}
