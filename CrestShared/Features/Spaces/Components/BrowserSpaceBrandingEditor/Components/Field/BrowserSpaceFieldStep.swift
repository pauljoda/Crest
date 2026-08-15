import SwiftUI

/// The field mode, curated palette, and individual tincture controls.
struct BrowserSpaceFieldStep: View {
    @Binding var branding: BrowserSpaceBranding
    let compact: Bool

    var body: some View {
        BrowserSpaceForgeSection(
            step: .field,
            value: branding.colors.map(\.title).joined(separator: " · "),
            caption: "Start with a restrained palette, then make any color your own."
        ) {
            Picker("Appearance", selection: $branding.editorThemeMode) {
                ForEach(BrowserSpaceThemeMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .tint(CrestBrandTheme.accent)

            LazyVGrid(
                columns: [
                    GridItem(
                        .adaptive(
                            minimum: compact
                                ? BrowserSpaceForgeMetrics.compactCrestCardMinimumWidth
                                : BrowserSpaceForgeMetrics.crestCardMinimumWidth),
                        spacing: BrowserSpaceForgeMetrics.gridSpacing
                    )
                ],
                alignment: .leading,
                spacing: BrowserSpaceForgeMetrics.gridSpacing
            ) {
                ForEach(BrowserSpaceBrandingPreset.curated) { preset in
                    BrowserSpacePresetCard(preset: preset, branding: $branding)
                }
            }

            HStack(
                alignment: .top,
                spacing: compact ? CrestSpacing.small : CrestSpacing.medium
            ) {
                ForEach(BrowserSpaceBrandColorRole.allCases) { role in
                    BrowserSpacePaletteSlot(
                        role: role,
                        color: $branding.editorColor(for: role),
                        canAdd: role.rawValue == branding.colors.count,
                        canRemove: role.rawValue == branding.colors.count - 1
                            && branding.colors.count > 1,
                        compact: compact,
                        addColor: { $branding.editorAddColor(for: role) },
                        removeColor: { $branding.editorRemoveColor(for: role) }
                    )
                }
            }
        }
    }
}

#Preview("Branding Editor — Field Step") {
    @Previewable @State var branding = BrowserSpaceBrandingPreviewFixture.crestBranding

    ScrollView {
        BrowserSpaceFieldStep(
            branding: $branding,
            compact: false
        )
        .padding(CrestSpacing.large)
    }
    .frame(width: 620, height: 760)
}
