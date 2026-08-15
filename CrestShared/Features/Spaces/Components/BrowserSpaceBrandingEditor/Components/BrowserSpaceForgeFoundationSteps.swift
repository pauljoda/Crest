import SwiftUI

struct BrowserSpaceForgeFoundationSteps: View {
    @Binding var branding: BrowserSpaceBranding
    @Binding var symbol: String
    let compact: Bool
    let showsPreview: Bool

    var body: some View {
        Group {
            if showsPreview {
                BrowserSpaceEditorPreview(
                    branding: branding,
                    symbol: symbol,
                    compact: compact
                )
            }

            BrowserSpaceFieldStep(branding: $branding, compact: compact)
            BrowserSpacePatternStep(branding: $branding, compact: compact)
            BrowserSpaceMarkStep(
                branding: $branding,
                symbol: $symbol,
                compact: compact
            )
        }
    }
}

#Preview("Branding Editor — Foundation Steps") {
    @Previewable @State var branding = BrowserSpaceBrandingPreviewFixture.gradientBranding
    @Previewable @State var symbol = BrowserSpaceSimpleSymbol.creative.rawValue

    ScrollView {
        BrowserSpaceForgeFoundationSteps(
            branding: $branding,
            symbol: $symbol,
            compact: true,
            showsPreview: true
        )
        .padding(CrestSpacing.medium)
    }
    .frame(width: 390, height: 760)
}
