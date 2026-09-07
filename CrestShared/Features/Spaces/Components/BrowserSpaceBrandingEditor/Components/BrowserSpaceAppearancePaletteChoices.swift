import SwiftUI

struct BrowserSpaceAppearancePaletteChoices: View {
    @Binding var branding: BrowserSpaceBranding
    let compact: Bool

    private var sectionSpacing: CGFloat {
        #if os(macOS)
            24
        #else
            28
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: sectionSpacing) {
            Text("Individual colors").font(.headline)
            HStack(alignment: .top, spacing: 16) {
                ForEach(BrowserSpaceBrandColorRole.allCases) { role in
                    BrowserSpacePaletteSlot(
                        role: role, color: $branding.editorColor(for: role),
                        canAdd: role.rawValue == branding.colors.count,
                        canRemove: role.rawValue == branding.colors.count - 1 && branding.colors.count > 1,
                        compact: true,
                        addColor: { $branding.editorAddColor(for: role) },
                        removeColor: { $branding.editorRemoveColor(for: role) }
                    )
                }
            }
            Text("Palettes").font(.headline)
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: compact ? 2 : 3), spacing: 14
            ) {
                ForEach(BrowserSpaceBrandingPreset.curated) { preset in
                    BrowserSpaceOptionCard(
                        title: preset.titleKey, isSelected: preset.colors == branding.colors,
                        tint: .accentColor,
                        select: { branding = preset.applyingPalette(to: branding) }
                    ) {
                        HStack(spacing: 0) {
                            ForEach(Array(preset.colors.enumerated()), id: \.offset) { _, color in
                                color.color
                            }
                        }
                        .frame(height: 56)
                        .clipShape(.rect(cornerRadius: 10))
                    }
                }
            }
        }
    }
}
