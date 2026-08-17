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
