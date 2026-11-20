import SwiftUI

/// One layer above the sidebar's base UI: the device's surface material in
/// `shape`, in the scheme its material color gives it, or a sheet of Crest's
/// light paper where the layer is a selection, with an accent tint and a
/// hover tint laid over it.
struct CrestSurfaceLayer<LayerShape: Shape>: View {
    let shape: LayerShape
    var tint: Color? = nil
    var hoverTint: Color? = nil
    /// Whether the layer is a sheet of Crest's paper, opaque and light on
    /// every Space, rather than the device's material.
    var isPaper = false

    @Environment(\.crestSurfaceMaterial) private var materialOverride
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.deviceColorScheme) private var deviceColorScheme

    var body: some View {
        ground
            .overlay {
                if let tint { shape.fill(tint) }
            }
            .overlay {
                if let hoverTint { shape.fill(hoverTint) }
            }
            .environment(\.colorScheme, scheme)
    }

    /// The scheme the layer draws in: light on paper, which is always light,
    /// else the one the device's material color gives it.
    private var scheme: ColorScheme {
        isPaper ? .light : CrestSurfaceTone.shownScheme(over: colorScheme, window: deviceColorScheme)
    }

    @ViewBuilder
    private var ground: some View {
        if isPaper {
            shape.fill(CrestBrandTheme.surface)
        } else {
            shape.fill(CrestSurfaceMaterial.shown(materialOverride).material)
        }
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
            Text(verbatim: "Paper")
                .font(.caption)
                .padding(CrestSpacing.small)
                .background { CrestSurfaceLayer(shape: .rect(cornerRadius: CrestRadius.compact), isPaper: true) }
        }
        .padding()
        .background(.indigo.gradient)
    }
#endif
