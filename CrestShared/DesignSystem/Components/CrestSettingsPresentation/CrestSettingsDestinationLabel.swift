import SwiftUI

/// Shared settings-navigation label used by the native macOS and mobile shells.
struct CrestSettingsDestinationLabel: View {
    let title: LocalizedStringResource
    let subtitle: LocalizedStringResource
    let systemImage: String
    let color: Color
    var compact = false
    var castsShadow = false

    var body: some View {
        HStack(spacing: labelSpacing) {
            CrestIconTile(
                systemImage: systemImage,
                color: color,
                size: iconSize,
                symbolSize: symbolSize,
                cornerRadius: iconCornerRadius,
                castsShadow: castsShadow
            )

            VStack(
                alignment: .leading,
                spacing: CrestSettingsPresentationMetrics.titleSpacing
            ) {
                Text(title)
                    .font(CrestTypography.controlTitle)
                    .foregroundStyle(CrestColor.textPrimary)
                if !compact || BrowserSettingsVisualPolicy.showsSidebarSubtitles {
                    Text(subtitle)
                        .font(
                            compact
                                ? CrestTypography.compactMetadata
                                : CrestTypography.metadata
                        )
                        .foregroundStyle(CrestColor.textSecondary)
                        .lineLimit(1)
                }
            }

            if compact {
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(title))
        .accessibilityHint(Text(subtitle))
    }

    private var labelSpacing: CGFloat {
        compact
            ? CrestSettingsPresentationMetrics.compactLabelSpacing
            : CrestSpacing.medium
    }

    private var iconSize: CGFloat {
        compact
            ? BrowserSettingsVisualPolicy.sidebarIconSize
            : CrestSettingsPresentationMetrics.regularIconSize
    }

    private var symbolSize: CGFloat {
        compact
            ? CrestSettingsPresentationMetrics.compactSymbolSize
            : CrestSettingsPresentationMetrics.regularSymbolSize
    }

    private var iconCornerRadius: CGFloat {
        compact
            ? CrestSettingsPresentationMetrics.compactIconCornerRadius
            : CrestSettingsPresentationMetrics.regularIconCornerRadius
    }
}
