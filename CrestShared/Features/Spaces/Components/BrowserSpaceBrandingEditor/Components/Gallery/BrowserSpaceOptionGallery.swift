import SwiftUI

/// The common adaptive gallery used by every forge option family.
struct BrowserSpaceOptionGallery<
    Option: Hashable & BrowserSpaceHeraldicTerm,
    Artwork: View
>: View {
    let options: [Option]
    let minimumWidth: CGFloat
    let isSelected: (Option) -> Bool
    let select: (Option) -> Void
    @ViewBuilder let artwork: (Option) -> Artwork

    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(
                    .adaptive(minimum: minimumWidth),
                    spacing: BrowserSpaceForgeMetrics.gridSpacing
                )
            ],
            alignment: .leading,
            spacing: BrowserSpaceForgeMetrics.gridSpacing
        ) {
            ForEach(options, id: \.self) { option in
                BrowserSpaceOptionCard(
                    title: option.titleKey,
                    isSelected: isSelected(option),
                    tint: CrestBrandTheme.accent,
                    select: { select(option) }
                ) {
                    artwork(option)
                }
            }
        }
    }
}

#Preview("Branding Editor — Option Gallery") {
    @Previewable @State var branding = BrowserSpaceBrandingPreviewFixture.crestBranding

    BrowserSpaceOptionGallery(
        options: BrowserSpaceCrestBackplate.allCases,
        minimumWidth: BrowserSpaceForgeMetrics.crestCardMinimumWidth,
        isSelected: { option in
            option == branding.crest.backplate
        },
        select: { option in
            $branding.editorUpdateCrest { $0.backplate = option }
        },
        artwork: { option in
            BrowserSpaceCrestIcon(
                branding: $branding.editorPreview {
                    $0.crest.backplate = option
                },
                size: BrowserSpaceForgeMetrics.crestThumbnailSize,
                rasterizesLayers: false
            )
        }
    )
    .padding(CrestSpacing.large)
    .frame(width: 620)
}
