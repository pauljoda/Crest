import SwiftUI

/// Publishes the desktop's focused-window transparency to shared settings
/// previews, which have no way to reach a macOS-only store themselves.
struct BrowserPlatformSettingsAtmosphereModifier: ViewModifier {
    @Environment(BrowserWindowTransparencyStore.self) private var transparency

    func body(content: Content) -> some View {
        content.environment(
            \.browserSettingsAtmosphereOpacity,
            BrowserWindowTransparencyPolicy.baseLayerOpacity(
                isEnabled: transparency.isEnabled,
                strength: transparency.strength,
                isWindowFocused: true
            )
        )
    }
}
