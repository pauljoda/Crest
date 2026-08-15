import SwiftUI

struct BrowserSpaceCrestOrdinaryShape: View {
    let ordinary: BrowserSpaceCrestOrdinary
    let color: Color
    let size: CGFloat

    var body: some View {
        ZStack {
            BrowserSpaceCrestOrdinaryBar(ordinary: ordinary, color: color, size: size)
            BrowserSpaceCrestOrdinarySymbol(ordinary: ordinary, color: color, size: size)
            BrowserSpaceCrestOrdinaryChief(ordinary: ordinary, color: color, size: size)
        }
        .frame(width: size, height: size)
    }
}

#Preview("Crest Ordinary Shape") {
    BrowserSpaceCrestOrdinaryShape(
        ordinary: .bend,
        color: BrowserSpaceBrandColor.lionGold.color,
        size: 112
    )
    .background(BrowserSpaceBrandColor.lionCrimson.color)
    .clipShape(.rect(cornerRadius: CrestRadius.card))
    .padding()
}
