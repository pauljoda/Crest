import SwiftUI

struct BrowserSpaceBannerBackground: View {
    let branding: SpaceBranding

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    private let previewReduceTransparency: Bool?
    private let previewContrast: ColorSchemeContrast?

    init(branding: SpaceBranding) {
        self.branding = branding
        previewReduceTransparency = nil
        previewContrast = nil
    }

    init(
        previewBranding branding: SpaceBranding,
        reduceTransparency: Bool,
        contrast: ColorSchemeContrast
    ) {
        self.branding = branding
        previewReduceTransparency = reduceTransparency
        previewContrast = contrast
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                CrestColor.windowBackground
                BrowserSpaceThemeField(
                    themeMode: branding.themeMode,
                    bannerPattern: branding.bannerPattern,
                    sidebarFill: resolvedFill,
                    fills: resolvedFills,
                    size: geometry.size
                )
                .opacity(fieldOpacity)

                // The readability fade darkens the colors under light text and
                // lightens them under dark text.
                if readabilityOpacity > 0 {
                    (branding.foregroundTone(over: colorScheme) == .dark ? Color.white : Color.black)
                        .opacity(readabilityOpacity)
                }

                if branding.textureStrength > 0 {
                    CrestGrain(style: .fine)
                        .blendMode(effectiveReduceTransparency ? .normal : .softLight)
                        .opacity(branding.textureStrength * CrestGrainMetrics.fullOpacity)
                }
            }
            .clipped()
        }
        .accessibilityHidden(true)
    }

    /// The sidebar's colors as its gradient runs them.
    private var resolvedFill: CrestColorFill {
        CrestColorFill(
            branding.colors.isEmpty ? [SpaceBranding.fallbackColor] : Array(branding.colors),
            kind: CrestGradientKind(branding.gradientKind), degrees: branding.gradientAngle)
    }

    /// The palette's colors as a banner fills them, each running into its
    /// own gradient where it has one.
    private var resolvedFills: [AnyShapeStyle] {
        branding.colors.isEmpty
            ? [AnyShapeStyle(SpaceBranding.fallbackColor.color)]
            : branding.colors.indices.map { branding.slotFill($0).style }
    }

    private var fieldOpacity: Double {
        effectiveReduceTransparency
            ? max(branding.bannerStrength, 0.85) : branding.bannerStrength
    }

    private var readabilityOpacity: Double {
        let configured =
            effectiveReduceTransparency
            ? max(branding.readabilityFade, 0.42)
            : branding.readabilityFade
        let increasedContrast = effectiveContrast == .increased ? 0.1 : 0
        return min(configured * 0.55 + increasedContrast, 0.7)
    }

    private var effectiveReduceTransparency: Bool {
        previewReduceTransparency ?? reduceTransparency
    }

    private var effectiveContrast: ColorSchemeContrast {
        previewContrast ?? contrast
    }
}

#if DEBUG
    #Preview("Banner and gradient") {
        HStack(spacing: 16) {
            BrowserSpaceBannerBackground(branding: BrowserSpaceBrandingPreviewFixture.bannerBranding)
            BrowserSpaceBannerBackground(branding: BrowserSpaceBrandingPreviewFixture.gradientBranding)
        }.frame(width: 500, height: 360).padding()
    }
#endif
