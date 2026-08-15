import SwiftUI

struct BrowserSpaceCrestOrdinarySymbol: View {
    let ordinary: BrowserSpaceCrestOrdinary
    let color: Color
    let size: CGFloat

    @ViewBuilder
    var body: some View {
        if let rendering = ordinary.symbolRendering {
            Image(systemName: rendering.systemImage)
                .font(.system(size: size * rendering.sizeFactor, weight: .black))
                .foregroundStyle(color)
                .offset(y: size * rendering.verticalOffsetFactor)
        }
    }
}

#Preview("Crest Ordinary Symbol") {
    BrowserSpaceCrestOrdinarySymbol(
        ordinary: .chevron,
        color: BrowserSpaceBrandColor.winterIce.color,
        size: 112
    )
    .frame(width: 112, height: 112)
    .background(BrowserSpaceBrandColor.winterSlate.color)
    .clipShape(.rect(cornerRadius: CrestRadius.card))
    .padding()
}
