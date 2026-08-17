import SwiftUI

/// A crest-sized live artifact for judging the full layered composition.
struct BrowserSpaceCrestArtifactPreview: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let branding: BrowserSpaceBranding
    let compact: Bool

    private var crestSummary: String {
        let crest = branding.crest
        return [
            crest.backplate.title,
            crest.fieldDivision.title,
            crest.ordinary.title,
            crest.symbol.title,
            crest.trim.title,
        ].joined(separator: ", ")
    }

    var body: some View {
        ZStack {
            BrowserSpaceBannerBackground(branding: branding)
            BrowserSpaceCrestIcon(
                branding: branding,
                size: compact
                    ? BrowserSpaceForgeMetrics.compactCrestArtifactSize
                    : BrowserSpaceForgeMetrics.crestArtifactSize
            )
        }
        .frame(maxWidth: .infinity)
        .frame(
            height: compact
                ? BrowserSpaceForgeMetrics.compactBannerArtifactHeight
                : BrowserSpaceForgeMetrics.bannerArtifactHeight
        )
        .clipShape(.rect(cornerRadius: CrestRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: CrestRadius.card, style: .continuous)
                .strokeBorder(CrestBrandTheme.line, lineWidth: CrestLayout.hairline)
        }
        .animation(
            BrowserVisualAccessibilityPolicy.animation(
                CrestMotion.pane,
                reduceMotion: reduceMotion
            ),
            value: branding
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Live crest preview")
        .accessibilityValue(crestSummary)
        .accessibilityIdentifier("space-branding-crest-preview")
    }
}
