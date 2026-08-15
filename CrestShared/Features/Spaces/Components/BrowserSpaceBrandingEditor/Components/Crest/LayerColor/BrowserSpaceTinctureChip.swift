import SwiftUI

struct BrowserSpaceTinctureChip: View {
    let title: LocalizedStringKey
    let role: BrowserSpaceBrandColorRole
    let color: Color
    @Binding var selection: Int

    private var isSelected: Bool { selection == role.rawValue }

    var body: some View {
        Button {
            selection = role.rawValue
        } label: {
            Circle()
                .fill(color)
                .frame(
                    width: BrowserSpaceForgeMetrics.paletteColorDiameter,
                    height: BrowserSpaceForgeMetrics.paletteColorDiameter
                )
                .overlay {
                    Circle().strokeBorder(
                        isSelected ? CrestBrandTheme.accent : CrestColor.subtleBorder,
                        lineWidth: isSelected
                            ? CrestSelectableCardMetrics.selectedBorderWidth
                            : CrestSelectableCardMetrics.restingBorderWidth
                    )
                }
                .frame(
                    width: CrestLayout.minimumHitTarget,
                    height: CrestLayout.minimumHitTarget
                )
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(role.title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview("Branding Editor — Tincture Chip") {
    @Previewable @State var selection =
        BrowserSpaceBrandingPreviewFixture.crestBranding.crest.symbolColorIndex
    let role = BrowserSpaceBrandColorRole.secondary

    BrowserSpaceTinctureChip(
        title: "Charge color",
        role: role,
        color: BrowserSpaceBrandingPreviewFixture.crestBranding.colors[role.rawValue].color,
        selection: $selection
    )
    .padding(CrestSpacing.large)
}
