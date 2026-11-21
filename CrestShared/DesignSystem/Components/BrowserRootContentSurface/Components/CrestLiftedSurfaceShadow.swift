import SwiftUI

/// Casts only the exterior part of a rounded surface's shadow.
///
/// The shadow is the shape's own, which Core Animation composites on the GPU.
/// Drawing it into a canvas instead blurred the whole page on the CPU at every
/// step of a window, split or sidebar resize.
struct CrestLiftedSurfaceShadow: View {
    let cornerRadius: CGFloat
    /// The surface's elevation, or nil while it casts no shadow.
    let elevation: CrestElevation?

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if let elevation, elevation.staysUnderReducedTransparency || !reduceTransparency {
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            // Inset, so the cut below covers the casting shape's soft edge.
            shape.inset(by: 1)
                .fill(.black)
                .crestElevation(elevation)
                // A translucent surface must not show its own shadow through it.
                .mask {
                    Rectangle()
                        .padding(-drawingOutset)
                        .overlay { shape.blendMode(.destinationOut) }
                        .compositingGroup()
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// How far past the shape the shadow reaches, which the cut must cover.
    private var drawingOutset: CGFloat {
        guard let elevation else { return 0 }
        return elevation.radius * 2 + max(abs(elevation.x), abs(elevation.y))
    }
}
