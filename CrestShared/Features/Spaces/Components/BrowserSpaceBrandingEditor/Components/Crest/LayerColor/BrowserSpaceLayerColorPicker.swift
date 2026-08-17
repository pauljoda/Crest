import SwiftUI

/// Selects the semantic palette role used to draw one crest layer.
struct BrowserSpaceLayerColorPicker: View {
    let title: LocalizedStringKey
    let branding: BrowserSpaceBranding
    @Binding var selection: Int

    private var availableRoles: [BrowserSpaceBrandColorRole] {
        BrowserSpaceBrandColorRole.allCases.filter {
            branding.colors.indices.contains($0.rawValue)
        }
    }

    var body: some View {
        HStack(spacing: CrestSpacing.small) {
            Text(title)
                .font(CrestTypography.metadata)
                .foregroundStyle(CrestColor.textSecondary)

            Spacer(minLength: CrestSpacing.small)

            ForEach(availableRoles) { role in
                BrowserSpaceTinctureChip(
                    title: title,
                    role: role,
                    color: branding.colors[role.rawValue].color,
                    selection: $selection
                )
            }
        }
        .frame(minHeight: CrestLayout.minimumHitTarget)
        .accessibilityElement(children: .contain)
    }
}
