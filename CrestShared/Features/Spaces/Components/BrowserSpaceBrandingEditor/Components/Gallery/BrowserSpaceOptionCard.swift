import SwiftUI

/// A rendered forge option using the app-wide selectable-card grammar.
struct BrowserSpaceOptionCard<Artwork: View>: View {
    let title: LocalizedStringKey
    var spokenValue: Text?
    let isSelected: Bool
    var identifier: String?
    let tint: Color
    let select: () -> Void
    @ViewBuilder let artwork: Artwork

    var body: some View {
        Button(action: select) {
            VStack(spacing: CrestSpacing.small) {
                artwork
                Text(title)
                    .font(CrestTypography.compactMetadata)
                    .foregroundStyle(CrestColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(BrowserSpaceForgeMetrics.optionLabelMinimumScale)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(
            CrestSelectableCardStyle(isSelected: isSelected, tint: tint)
        )
        .accessibilityLabel(Text(title))
        .crestAccessibilityValue(spokenValue)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .crestAccessibilityIdentifier(identifier)
    }
}

#Preview("Branding Option Cards") {
    HStack(spacing: BrowserSpaceForgeMetrics.gridSpacing) {
        BrowserSpaceOptionCard(
            title: "Winter",
            isSelected: true,
            tint: CrestBrandTheme.accent,
            select: {},
            artwork: {
                BrowserSpaceBannerBackground(
                    branding: BrowserSpaceBrandingPreviewFixture.bannerBranding
                )
                .frame(height: BrowserSpaceForgeMetrics.patternBannerHeight)
                .clipShape(
                    .rect(cornerRadius: BrowserSpaceForgeMetrics.artworkCornerRadius)
                )
            }
        )

        BrowserSpaceOptionCard(
            title: "Storm",
            isSelected: false,
            tint: CrestBrandTheme.accent,
            select: {},
            artwork: {
                BrowserSpaceBannerBackground(
                    branding: BrowserSpaceBrandingPreviewFixture.gradientBranding
                )
                .frame(height: BrowserSpaceForgeMetrics.patternBannerHeight)
                .clipShape(
                    .rect(cornerRadius: BrowserSpaceForgeMetrics.artworkCornerRadius)
                )
            }
        )
    }
    .frame(width: 280)
    .padding(CrestSpacing.large)
}
