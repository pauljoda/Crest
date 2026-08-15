import SwiftUI

struct BrowserSpaceDiagonalLowerBannerShape: Shape {
    let size: CGSize

    func path(in _: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: 0, y: size.height * 0.68))
            path.addLine(to: CGPoint(x: size.width, y: size.height * 0.50))
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.addLine(to: CGPoint(x: 0, y: size.height))
            path.closeSubpath()
        }
    }
}

#Preview("Diagonal Lower Banner Shape") {
    BrowserSpaceDiagonalLowerBannerShape(size: CGSize(width: 240, height: 120))
        .fill(BrowserSpaceBrandColor.ember.color)
        .frame(width: 240, height: 120)
        .padding()
}
