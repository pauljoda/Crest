import SwiftUI

/// The banner forge: the whole of a Space's visual identity, composed in the
/// order arms are composed.
struct BrowserSpaceBrandingEditor: View {
    @Binding var branding: BrowserSpaceBranding
    @Binding var symbol: String
    var compact = false
    var showsPreview = true

    var body: some View {
        LazyVStack(alignment: .leading, spacing: CrestSpacing.extraExtraLarge) {
            BrowserSpaceForgeFoundationSteps(
                branding: $branding,
                symbol: $symbol,
                compact: compact,
                showsPreview: showsPreview
            )

            if branding.iconStyle == .layeredCrest {
                BrowserSpaceForgeCrestSteps(
                    branding: $branding,
                    compact: compact
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Space branding builder")
    }
}

#Preview("Branding Editor — Layered Crest") {
    @Previewable @State var branding = BrowserSpaceBrandingPreviewFixture.crestBranding
    @Previewable @State var symbol = BrowserSpaceSimpleSymbol.work.rawValue

    ScrollView {
        BrowserSpaceBrandingEditor(
            branding: $branding,
            symbol: $symbol
        )
        .padding(CrestSpacing.large)
    }
    .frame(width: 680, height: 880)
}
