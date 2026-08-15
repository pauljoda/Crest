import SwiftUI

struct BrowserSpaceEditorIdentityPreview: View {
    let branding: BrowserSpaceBranding
    let symbol: String

    var body: some View {
        Group {
            if branding.iconStyle == .layeredCrest {
                BrowserSpaceCrestIcon(
                    branding: branding,
                    size: BrowserSpaceForgeMetrics.previewIdentitySize
                )
            } else {
                Image(systemName: symbol)
                    .font(
                        .system(
                            size: BrowserSpaceForgeMetrics.previewSymbolPointSize,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(branding.primaryColor.color)
                    .frame(
                        width: BrowserSpaceForgeMetrics.previewIdentitySize,
                        height: BrowserSpaceForgeMetrics.previewIdentitySize
                    )
            }
        }
    }
}

#Preview("Editor Identity — Layered Crest") {
    BrowserSpaceEditorIdentityPreview(
        branding: BrowserSpaceBrandingPreviewFixture.crestBranding,
        symbol: BrowserSpaceSimpleSymbol.work.rawValue
    )
    .padding(CrestSpacing.large)
}

#Preview("Editor Identity — Simple Symbol") {
    BrowserSpaceEditorIdentityPreview(
        branding: BrowserSpaceBrandingPreviewFixture.bannerBranding,
        symbol: BrowserSpaceSimpleSymbol.creative.rawValue
    )
    .padding(CrestSpacing.large)
}
