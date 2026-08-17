import SwiftUI

struct BrowserSpaceCrestChargeView: View {
    let symbol: BrowserSpaceCrestSymbol
    let layout: BrowserSpaceCrestChargeLayout
    let color: Color
    let size: CGFloat

    @ViewBuilder
    var body: some View {
        switch layout {
        case .single:
            BrowserSpaceCrestChargeImage(
                symbol: symbol,
                size: size,
                scale: 0.31,
                color: color
            )
        case .paired:
            HStack(spacing: size * 0.07) {
                BrowserSpaceCrestChargeImage(
                    symbol: symbol,
                    size: size,
                    scale: 0.22,
                    color: color
                )
                BrowserSpaceCrestChargeImage(
                    symbol: symbol,
                    size: size,
                    scale: 0.22,
                    color: color
                )
            }
        case .trio:
            VStack(spacing: -size * 0.03) {
                BrowserSpaceCrestChargeImage(
                    symbol: symbol,
                    size: size,
                    scale: 0.18,
                    color: color
                )
                HStack(spacing: size * 0.07) {
                    BrowserSpaceCrestChargeImage(
                        symbol: symbol,
                        size: size,
                        scale: 0.18,
                        color: color
                    )
                    BrowserSpaceCrestChargeImage(
                        symbol: symbol,
                        size: size,
                        scale: 0.18,
                        color: color
                    )
                }
            }
        }
    }
}
