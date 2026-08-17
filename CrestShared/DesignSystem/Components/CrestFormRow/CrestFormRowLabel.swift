import SwiftUI

/// Reusable label content for native `NavigationLink`, `Toggle`, `Picker`, and
/// `LabeledContent` rows.
struct CrestFormRowLabel: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    let systemImage: String
    var tint: Color = CrestBrandTheme.accent

    var body: some View {
        HStack(spacing: CrestFormRowMetrics.contentSpacing) {
            CrestIconTile(
                systemImage: systemImage,
                color: tint,
                size: CrestFormRowMetrics.iconTileSize,
                symbolSize: CrestFormRowMetrics.iconSymbolSize
            )

            VStack(alignment: .leading, spacing: CrestFormRowMetrics.titleSpacing) {
                Text(title)
                    .font(CrestTypography.controlTitle)
                    .foregroundStyle(CrestColor.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(CrestTypography.metadata)
                        .foregroundStyle(CrestColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
