import SwiftUI

/// A Space's two colors as color wells, each one color or a gradient: its
/// Background, which the sidebar wears, and its Accent, which its crest's
/// emblem and border, its icon and its highlights wear. Setup's Space page
/// shows them; a Space's appearance in Settings shows them on its stage.
struct BrowserSpaceColorWells: View {
    // MARK: - Variables

    @Binding var branding: SpaceBranding

    /// The Space's texture, which its Background's picker sets.
    private var texture: Binding<Double> {
        Binding(
            get: { branding.textureStrength },
            set: { strength in
                $branding.editorUpdate {
                    $0.textureStrength = strength
                    $0.hasCustomAppearance = true
                }
            })
    }

    // MARK: - Actions - Drawing

    var body: some View {
        HStack(alignment: .top, spacing: CrestSpacing.large) {
            well(.background)
            well(.accent)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("space-color-wells")
    }

    private func well(_ role: BrowserSpaceBrandColorRole) -> some View {
        VStack(spacing: CrestSpacing.extraSmall) {
            CrestColorWell(
                title: role.title,
                fill: Binding(
                    get: { branding.wellFill(role) },
                    set: { fill in $branding.editorUpdate { $0.setWellFill(fill, of: role) } }),
                texture: role == .background ? texture : nil)
            Text(role.title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
