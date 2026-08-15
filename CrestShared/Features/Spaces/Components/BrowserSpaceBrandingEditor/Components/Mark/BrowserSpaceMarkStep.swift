import SwiftUI

/// Chooses between a simple SF Symbol and the layered crest editor.
struct BrowserSpaceMarkStep: View {
    @Binding var branding: BrowserSpaceBranding
    @Binding var symbol: String
    let compact: Bool

    var body: some View {
        BrowserSpaceForgeSection(
            step: .mark,
            value: branding.iconStyle.title,
            caption: "How this Space signs itself in the sidebar and on its tabs."
        ) {
            Picker("Space icon", selection: $branding.editorIconStyle) {
                ForEach(BrowserSpaceIconStyle.allCases, id: \.self) { style in
                    Text(style.titleKey).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .tint(CrestBrandTheme.accent)

            if branding.iconStyle == .layeredCrest {
                BrowserSpaceCrestArtifactPreview(
                    branding: branding,
                    compact: compact
                )
            } else {
                BrowserSpaceSimpleSymbolPicker(symbol: $symbol)
            }
        }
    }
}

#Preview("Mark Step — Layered Crest") {
    @Previewable @State var branding = BrowserSpaceBrandingPreviewFixture.crestBranding
    @Previewable @State var symbol = BrowserSpaceSimpleSymbol.work.rawValue

    BrowserSpaceMarkStep(
        branding: $branding,
        symbol: $symbol,
        compact: false
    )
    .frame(width: BrowserSpaceForgeMetrics.previewMaximumWidth)
    .padding(CrestSpacing.large)
}

#Preview("Mark Step — Simple Symbol") {
    @Previewable @State var branding = BrowserSpaceBrandingPreviewFixture.bannerBranding
    @Previewable @State var symbol = BrowserSpaceSimpleSymbol.creative.rawValue

    BrowserSpaceMarkStep(
        branding: $branding,
        symbol: $symbol,
        compact: true
    )
    .frame(width: BrowserSpaceForgeMetrics.previewMaximumWidth)
    .padding(CrestSpacing.large)
}
