import SwiftUI

struct BrowserSpaceChevronLowerBannerShape: Shape {
    let size: CGSize

    func path(in _: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: 0, y: size.height * 0.62))
            path.addLine(to: CGPoint(x: size.width * 0.5, y: size.height * 0.78))
            path.addLine(to: CGPoint(x: size.width, y: size.height * 0.62))
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.addLine(to: CGPoint(x: 0, y: size.height))
            path.closeSubpath()
        }
    }
}

#Preview("Chevron Lower Banner Shape") {
    BrowserSpaceChevronLowerBannerShape(size: CGSize(width: 240, height: 120))
        .fill(BrowserSpaceBrandColor.indigo.color)
        .frame(width: 240, height: 120)
        .padding()
}
