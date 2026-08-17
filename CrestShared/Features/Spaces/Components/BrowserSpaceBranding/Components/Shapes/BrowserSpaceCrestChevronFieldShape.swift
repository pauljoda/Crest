import SwiftUI

struct BrowserSpaceCrestChevronFieldShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: 0, y: rect.height * 0.48))
            path.addLine(to: CGPoint(x: rect.width * 0.5, y: rect.height * 0.68))
            path.addLine(to: CGPoint(x: rect.width, y: rect.height * 0.48))
            path.addLine(to: CGPoint(x: rect.width, y: rect.height))
            path.addLine(to: CGPoint(x: 0, y: rect.height))
            path.closeSubpath()
        }
    }
}
