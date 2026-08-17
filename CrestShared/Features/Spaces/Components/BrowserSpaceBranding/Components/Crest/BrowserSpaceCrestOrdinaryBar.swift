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
