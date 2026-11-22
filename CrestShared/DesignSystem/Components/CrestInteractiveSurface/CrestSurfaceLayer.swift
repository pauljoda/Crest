import SwiftUI

/// One layer above the sidebar's base UI: the device's surface material in
/// `shape`, in the scheme its material color gives it, or a sheet of Crest's
/// light paper where the layer is a selection, as solid as the selection
/// asks and over a ground of its own where it brings one, with an accent
/// tint and a hover tint laid over it.
struct CrestSurfaceLayer<LayerShape: Shape>: View {
    let shape: LayerShape
    var tint: Color? = nil
    var hoverTint: Color? = nil
    /// The sheet of Crest's paper the layer is, light on every Space, or nil
    /// for the device's material.
    var paper: CrestPaperSheet? = nil

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
        paper != nil ? .light : CrestSurfaceTone.shownScheme(over: colorScheme, window: deviceColorScheme)
    }

    @ViewBuilder
    private var ground: some View {
        if let paper {
            shape.fill(CrestBrandTheme.surface.opacity(paper.opacity))
                .background {
                    if let ground = paper.ground { shape.fill(ground) }
                }
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
                .background { CrestSurfaceLayer(shape: .rect(cornerRadius: CrestRadius.compact), paper: .opaque) }
            Text(verbatim: "Paper over a ground")
                .font(.caption)
                .padding(CrestSpacing.small)
                .background {
                    CrestSurfaceLayer(
                        shape: .rect(cornerRadius: CrestRadius.compact),
                        paper: CrestPaperSheet(opacity: CrestOpacity.selectedTabPaper, ground: .orange))
                }
        }
        .padding()
        .background(.indigo.gradient)
    }
#endif
