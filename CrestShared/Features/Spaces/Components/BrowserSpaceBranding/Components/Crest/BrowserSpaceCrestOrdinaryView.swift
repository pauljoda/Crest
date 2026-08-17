import SwiftUI

struct BrowserSpaceCrestOrdinaryView: View {
    let ordinary: BrowserSpaceCrestOrdinary
    let backplateSymbol: String
    let outlineSystemImage: String?
    let color: Color
    let size: CGFloat

    @ViewBuilder
    var body: some View {
        if ordinary == .bordure, let outlineSystemImage {
            Image(systemName: outlineSystemImage)
                .font(.system(size: size * 0.72, weight: .black))
                .foregroundStyle(color)
        } else if ordinary != .none {
            BrowserSpaceCrestOrdinaryShape(
                ordinary: ordinary,
                color: color,
                size: size
            )
            .mask {
                BrowserSpaceCrestBackplateMask(
                    systemImage: backplateSymbol,
                    size: size
                )
            }
        }
    }
}
