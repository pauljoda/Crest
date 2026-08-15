import SwiftUI

struct BrowserSpaceCrestRasterization: ViewModifier {
    let enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.drawingGroup()
        } else {
            content
        }
    }
}

#Preview("Crest Rasterization", traits: .sizeThatFitsLayout) {
    BrowserSpaceCrestIcon(
        branding: BrowserSpaceBrandingPreviewFixture.crestBranding,
        size: 112,
        rasterizesLayers: false
    )
    .modifier(BrowserSpaceCrestRasterization(enabled: true))
    .padding()
    .preferredColorScheme(.light)
}
