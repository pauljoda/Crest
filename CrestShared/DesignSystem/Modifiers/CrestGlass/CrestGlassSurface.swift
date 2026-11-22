import SwiftUI

/// The surface a control floating on its own stands on: Liquid Glass where
/// the system draws it, and before macOS 26, which has no glass, the device's
/// surface material in the same shape, tinted the same way and lit under the
/// pointer.
struct CrestGlassSurface<SurfaceShape: Shape>: ViewModifier {
    // MARK: - Variables

    let shape: SurfaceShape
    /// The colour the surface takes, such as a Space's, or nil for clear glass.
    var tint: Color? = nil

    @State private var isHovering = false

    @available(macOS 26, *)
    private var glass: Glass {
        (tint.map { Glass.regular.tint($0) } ?? .regular).interactive()
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(glass, in: shape)
        } else {
            content
                .background {
                    CrestSurfaceLayer(shape: shape, tint: tint, hoverTint: isHovering ? CrestColor.hover : nil)
                }
                .onHover { isHovering = $0 }
        }
    }
}

extension View {
    /// Stands the view on Liquid Glass in `shape`, or before macOS 26 on the
    /// device's surface material.
    func crestGlass(tint: Color? = nil, in shape: some Shape) -> some View {
        modifier(CrestGlassSurface(shape: shape, tint: tint))
    }
}
