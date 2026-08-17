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
