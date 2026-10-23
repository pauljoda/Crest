import SwiftUI

/// A Space's look as a window draws it: as chosen in light, and in dark with
/// its colors dimmed as far as the device asks, under text that reads over
/// them.
extension SpaceBranding {
    // MARK: - Variables

    /// This look as the windows' appearance shows it now.
    @MainActor
    var shown: SpaceBranding {
        let appearance = BrowserDeviceAppearanceStore.shared
        return appearing(in: appearance.shownColorScheme, dimming: appearance.darkSpaceDimming)
    }

    // MARK: - Actions - Appearance

    /// This look drawn in `colorScheme`. Dark dims each color `dimming` of the
    /// way, from 0 to 1, toward a charcoal tint of its hue, eases the
    /// readability fade out as it does, and works its text tone out from the
    /// dimmed colors, so a text color chosen for the bright look never draws
    /// dark on dark. Light, or no dimming, draws the look as chosen.
    func appearing(in colorScheme: ColorScheme, dimming: Double) -> SpaceBranding {
        guard colorScheme == .dark, dimming > 0 else { return self }
        var look = self
        look.colors = ColorPalette(colors: colors.map { $0.dimmed(by: dimming) })
        look.readabilityFade = readabilityFade * (1 - dimming)
        look.textColorMode = .automatic
        return look
    }
}
