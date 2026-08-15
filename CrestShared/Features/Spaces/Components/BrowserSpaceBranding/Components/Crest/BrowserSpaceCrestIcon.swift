import SwiftUI

struct BrowserSpaceCrestIcon: View {
    let branding: BrowserSpaceBranding
    var size: CGFloat = 44
    var rasterizesLayers = true

    var body: some View {
        let crest = branding.crest
        ZStack {
            if let backplateSymbol = crest.backplate.systemImage {
                BrowserSpaceCrestField(
                    division: crest.fieldDivision,
                    primaryColor: color(at: crest.backplateColorIndex),
                    secondaryColor: color(at: crest.secondaryFieldColorIndex),
                    size: size
                )
                .mask {
                    BrowserSpaceCrestBackplateMask(
                        systemImage: backplateSymbol,
                        size: size
                    )
                }

                BrowserSpaceCrestOrdinaryView(
                    ordinary: crest.ordinary,
                    backplateSymbol: backplateSymbol,
                    outlineSystemImage: crest.backplate.outlineSystemImage,
                    color: color(at: crest.ordinaryColorIndex),
                    size: size
                )
            }

            BrowserSpaceCrestTrimView(
                trim: crest.trim,
                outlineSystemImage: crest.backplate.outlineSystemImage,
                color: color(at: crest.trimColorIndex),
                size: size
            )
            BrowserSpaceCrestChargeView(
                symbol: crest.symbol,
                layout: crest.chargeLayout,
                color: color(at: crest.symbolColorIndex),
                size: size
            )
        }
        .frame(width: size, height: size)
        .modifier(BrowserSpaceCrestRasterization(enabled: rasterizesLayers))
        .accessibilityHidden(true)
    }

    private func color(at index: Int) -> Color {
        let colors = branding.colors
        return colors[(0..<colors.count).contains(index) ? index : 0].color
    }
}

#Preview("Layered Crest Icon", traits: .sizeThatFitsLayout) {
    BrowserSpaceCrestIcon(
        branding: BrowserSpaceBrandingPreviewFixture.crestBranding,
        size: 112
    )
    .padding()
    .preferredColorScheme(.light)
}
