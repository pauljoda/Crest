import SwiftUI

/// The palette's own surface: the device's surface material, as the address
/// field it grows out of and the pins stand on, in the scheme the material
/// color gives it. Reduce Transparency draws the material opaque.
struct BrowserCommandPaletteShellMaterial: ViewModifier {
    let shape: RoundedRectangle

    func body(content: Content) -> some View {
        content.background { CrestSurfaceLayer(shape: shape) }
    }
}
