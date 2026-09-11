import SwiftUI

extension View {
    /// Matches a settings preview's atmosphere to this device's focused-window
    /// transparency.
    func browserPlatformSettingsAtmosphere() -> some View {
        modifier(BrowserPlatformSettingsAtmosphereModifier())
    }
}
