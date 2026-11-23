import SwiftUI

/// A Space's colors, one row each, every one a color or a gradient in its
/// well: its Background, which the sidebar wears, its Accent, which its
/// crest's emblem and border, its icon and its highlights wear, and its
/// Pattern while the sidebar draws a pattern. Each well opens the color
/// popover, which also takes a hex code for each of its colors. Setup's Space
/// page and a Space's appearance in Settings show them, above the presets.
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

    /// Background and Accent, and Pattern while the sidebar shows one.
    private var roles: [BrowserSpaceBrandColorRole] {
        branding.showsPattern ? BrowserSpaceBrandColorRole.all : [.background, .accent]
    }

    // MARK: - Actions - Drawing

    var body: some View {
        ForEach(roles) { role in
            row(role)
        }
    }

    private func row(_ role: BrowserSpaceBrandColorRole) -> some View {
        // The title and the well share one center line, as the well is taller
        // than a line of text.
        HStack(spacing: CrestSpacing.small) {
            Text(role.title)
            Spacer(minLength: CrestSpacing.medium)
            CrestColorWell(
                title: role.title,
                fill: Binding(
                    get: { branding.wellFill(role) },
                    set: { fill in $branding.editorUpdate { $0.setWellFill(fill, of: role) } }),
                texture: role == .background ? texture : nil)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("space-color-\(role.name)")
    }
}
