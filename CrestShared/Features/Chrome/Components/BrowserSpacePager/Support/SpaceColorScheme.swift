import SwiftUI

extension EnvironmentValues {
    /// The scheme the window draws in, under any Space's own: what controls
    /// that read the same on every Space wear.
    @Entry var deviceColorScheme: ColorScheme? = nil
}

/// Draws content in the scheme a Space's sidebar reads in over the window,
/// keeping the window's own scheme for the controls that read the same on
/// every Space.
///
/// The scheme follows the device's dark dimming, which a person drags. Working
/// it out here, rather than in the view that wraps the sidebar, keeps a drag to
/// this modifier: the sidebar under it re-renders only when the scheme itself
/// changes.
struct SpaceColorScheme: ViewModifier {
    /// The look of the Space the content belongs to, or nil for none, which
    /// draws dark.
    let branding: SpaceBranding?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.deviceColorScheme) private var deviceColorScheme

    func body(content: Content) -> some View {
        content
            .environment(\.colorScheme, branding?.shown.colorScheme(over: colorScheme) ?? .dark)
            .environment(\.deviceColorScheme, deviceColorScheme ?? colorScheme)
    }
}

/// Glass controls over a Space's sidebar, such as the address field, the
/// pins and the site controls they open, in the window's own light or dark
/// with its own text color, the same on every Space whatever its colors.
struct DeviceSurfaceAppearance: ViewModifier {
    @Environment(\.deviceColorScheme) private var deviceColorScheme
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            // The label color itself, not the Space ink a hierarchical style
            // would take its levels from.
            .foregroundStyle(Color.primary)
            .environment(\.spaceChromeForeground, nil)
            .environment(\.colorScheme, deviceColorScheme ?? colorScheme)
    }
}
