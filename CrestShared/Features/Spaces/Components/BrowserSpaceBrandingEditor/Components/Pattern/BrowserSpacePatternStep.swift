import SwiftUI

/// The banner cut or gradient rotation that lays out the Space field.
struct BrowserSpacePatternStep: View {
    @Binding var branding: BrowserSpaceBranding
    let compact: Bool

    @State private var isFineTuningExpanded = false

    var body: some View {
        BrowserSpaceForgeSection(
            step: .pattern,
            value: branding.themeMode == .banner
                ? branding.bannerPattern.title
                : "\(Int(branding.gradientAngle.rounded()))°",
            caption: "How the field is laid across the sidebar."
        ) {
            switch branding.themeMode {
            case .banner:
                BrowserSpaceOptionGallery(
                    options: BrowserSpaceBannerPattern.allCases,
                    minimumWidth: compact
                        ? BrowserSpaceForgeMetrics.compactPatternCardMinimumWidth
                        : BrowserSpaceForgeMetrics.patternCardMinimumWidth,
                    isSelected: { $0 == branding.bannerPattern },
                    select: { pattern in
                        $branding.editorUpdate { $0.bannerPattern = pattern }
                    }
                ) { pattern in
                    BrowserSpaceBannerBackground(
                        branding: $branding.editorPreview {
                            $0.bannerPattern = pattern
                        }
                    )
                    .frame(height: BrowserSpaceForgeMetrics.patternBannerHeight)
                    .clipShape(
                        .rect(
                            cornerRadius: BrowserSpaceForgeMetrics.artworkCornerRadius,
                            style: .continuous
                        ))
                }

                BrowserSpaceFineTuningControl(
                    branding: $branding,
                    isExpanded: $isFineTuningExpanded,
                    showsTextureControl: false
                )
            case .gradient:
                HStack(spacing: CrestSpacing.large) {
                    BrowserSpaceGradientAngleDial(
                        angle: $branding.editorGradientAngle,
                        color: branding.secondaryColor.color
                    )
                    .frame(
                        width: compact
                            ? BrowserSpaceForgeMetrics.compactGradientDialSize
                            : BrowserSpaceForgeMetrics.gradientDialSize,
                        height: compact
                            ? BrowserSpaceForgeMetrics.compactGradientDialSize
                            : BrowserSpaceForgeMetrics.gradientDialSize
                    )

                    VStack(alignment: .leading, spacing: CrestSpacing.extraSmall) {
                        Text("Gradient rotation")
                        Text(verbatim: "\(Int(branding.gradientAngle.rounded()))°")
                            .foregroundStyle(CrestColor.textSecondary)
                            .monospacedDigit()
                            .accessibilityLabel(
                                "\(Int(branding.gradientAngle.rounded())) degrees"
                            )
                            .accessibilityIdentifier(
                                "space-branding-gradient-angle-value"
                            )
                        Text("Drag the dial to rotate the gradient line.")
                            .font(CrestTypography.metadata)
                            .foregroundStyle(CrestColor.textSecondary)
                    }
                }

                BrowserSpaceFineTuningControl(
                    branding: $branding,
                    isExpanded: $isFineTuningExpanded,
                    showsTextureControl: true
                )
            }
        }
    }
}
