import SwiftUI

extension BrowserEngineRegistration {
    /// The WebKit compositions contribute their settings pane here. Chromium
    /// supplies this method from its own engine composition.
    @MainActor
    static func featureFlagsPane(profileID: UUID?) -> some View {
        BrowserPlatformWebKitFeatureFlagSettingsPane()
    }
}
