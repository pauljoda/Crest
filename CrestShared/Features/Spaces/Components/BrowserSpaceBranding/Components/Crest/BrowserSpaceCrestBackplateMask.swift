import SwiftUI

struct BrowserSpaceCrestBackplateMask: View {
    let systemImage: String
    let size: CGFloat

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.72, weight: .regular))
            .frame(width: size, height: size)
    }
}
