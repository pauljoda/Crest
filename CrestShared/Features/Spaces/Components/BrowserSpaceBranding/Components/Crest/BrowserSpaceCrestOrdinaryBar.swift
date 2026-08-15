import SwiftUI

struct BrowserSpaceCrestOrdinaryBar: View {
    let ordinary: BrowserSpaceCrestOrdinary
    let color: Color
    let size: CGFloat

    @ViewBuilder
    var body: some View {
        if let rendering = ordinary.barRendering {
            Rectangle()
                .fill(color)
                .frame(
                    width: rendering.widthFactor.map { size * $0 },
                    height: rendering.heightFactor.map { size * $0 }
                )
                .rotationEffect(.degrees(rendering.rotationDegrees))
        }
    }
}

#Preview("Crest Ordinary Bar") {
    BrowserSpaceCrestOrdinaryBar(
        ordinary: .bend,
        color: BrowserSpaceBrandColor.lionGold.color,
        size: 112
    )
    .frame(width: 112, height: 112)
    .background(BrowserSpaceBrandColor.lionCrimson.color)
    .clipShape(.rect(cornerRadius: CrestRadius.card))
    .padding()
}
