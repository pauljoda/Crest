import SwiftUI

struct BrowserSpaceCrestChargeImage: View {
    let symbol: BrowserSpaceCrestSymbol
    let size: CGFloat
    let scale: CGFloat
    let color: Color

    var body: some View {
        Image(systemName: symbol.systemImage)
            .font(.system(size: size * scale, weight: .bold))
            .foregroundStyle(color)
    }
}

#Preview("Crest Charge Image", traits: .sizeThatFitsLayout) {
    let branding = BrowserSpaceBrandingPreviewFixture.crestBranding

    BrowserSpaceCrestChargeImage(
        symbol: branding.crest.symbol,
        size: 112,
        scale: 0.31,
        color: branding.secondaryColor.color
    )
    .padding()
}
