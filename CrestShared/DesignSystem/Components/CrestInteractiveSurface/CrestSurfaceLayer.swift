import SwiftUI

/// One layer above the sidebar's base UI: the device's surface material in
/// `shape`, in the scheme its material color gives it, with an accent tint
/// and a hover tint laid over it.
struct CrestSurfaceLayer<LayerShape: Shape>: View {
    let shape: LayerShape
    var tint: Color? = nil
    var hoverTint: Color? = nil

    @Environment(\.crestSurfaceMaterial) private var materialOverride
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.deviceColorScheme) private var deviceColorScheme

    var body: some View {
        shape
            .fill(CrestSurfaceMaterial.shown(materialOverride).material)
            .overlay {
                if let tint { shape.fill(tint) }
            }
            .overlay {
                if let hoverTint { shape.fill(hoverTint) }
            }
            .environment(\.colorScheme, CrestSurfaceTone.shownScheme(over: colorScheme, window: deviceColorScheme))
    }
}

#if DEBUG
    #Preview("Surface materials") {
        HStack(spacing: CrestSpacing.small) {
            ForEach(CrestSurfaceMaterial.all, id: \.self) { surface in
                Text(surface.title)
                    .font(.caption)
                    .padding(CrestSpacing.small)
                    .background { CrestSurfaceLayer(shape: .rect(cornerRadius: CrestRadius.compact)) }
                    .environment(\.crestSurfaceMaterial, surface)
            }
        }
        .padding()
        .background(.indigo.gradient)
    }
#endif
