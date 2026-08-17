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
