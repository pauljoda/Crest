import SwiftUI

/// The palette's own surface: the device's surface material, as the address
/// field it grows out of and the pins stand on, in the scheme the material
/// color gives it, which what the palette shows reads in too. Reduce
/// Transparency draws the material opaque.
struct BrowserCommandPaletteShellMaterial: ViewModifier {
    let shape: RoundedRectangle

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.deviceColorScheme) private var deviceColorScheme

    func body(content: Content) -> some View {
        content
            .background { CrestSurfaceLayer(shape: shape) }
            .environment(\.colorScheme, CrestSurfaceTone.shownScheme(over: colorScheme, window: deviceColorScheme))
    }
}
