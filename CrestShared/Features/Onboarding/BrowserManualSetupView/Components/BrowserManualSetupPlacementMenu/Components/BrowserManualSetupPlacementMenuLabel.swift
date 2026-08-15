import SwiftUI

struct BrowserManualSetupPlacementMenuLabel: View {
    let placement: TabPlacement
    let symbol: String

    var body: some View {
        HStack(spacing: BrowserManualSetupPlacementMenuMetrics.itemSpacing) {
            Image(systemName: symbol)
            Text(
                BrowserManualSetupPlacementPresentation.title(for: placement)
            )
            Image(systemName: "chevron.down")
                .font(CrestTypography.compactMetadata.weight(.bold))
        }
        .font(CrestTypography.metadata.weight(.semibold))
        .foregroundStyle(CrestBrandTheme.accent)
        .padding(
            .horizontal,
            BrowserManualSetupPlacementMenuMetrics.horizontalPadding
        )
        .frame(height: BrowserManualSetupPlacementMenuMetrics.height)
        .background(
            CrestBrandTheme.accent.opacity(CrestButtonMetrics.tintRestFill),
            in: .capsule
        )
        .overlay {
            Capsule().strokeBorder(
                CrestBrandTheme.accent.opacity(CrestButtonMetrics.tintRestStroke),
                lineWidth: CrestButtonMetrics.quietStrokeWidth
            )
        }
    }
}

#Preview("Manual Setup Placement Label") {
    BrowserManualSetupPlacementMenuLabel(
        placement: .saved,
        symbol: "bookmark.fill"
    )
    .padding()
}
