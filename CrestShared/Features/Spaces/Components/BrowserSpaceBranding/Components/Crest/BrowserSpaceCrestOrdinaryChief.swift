import SwiftUI

struct BrowserSpaceCrestOrdinaryChief: View {
    let ordinary: BrowserSpaceCrestOrdinary
    let color: Color
    let size: CGFloat

    @ViewBuilder
    var body: some View {
        if ordinary == .chief {
            VStack(spacing: 0) {
                color.frame(height: size * 0.24)
                Spacer(minLength: 0)
            }
        }
    }
}
