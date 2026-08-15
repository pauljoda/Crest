import SwiftUI

struct CrestSkyPlaneShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(
            to: CGPoint(
                x: rect.minX + rect.width * 0.39,
                y: rect.minY + rect.height * 0.306
            )
        )
        path.addLine(
            to: CGPoint(
                x: rect.minX + rect.width * 0.762,
                y: rect.minY + rect.height * 0.306
            )
        )
        path.addLine(
            to: CGPoint(
                x: rect.minX + rect.width * 0.762,
                y: rect.minY + rect.height * 0.635
            )
        )
        path.addLine(
            to: CGPoint(
                x: rect.minX + rect.width * 0.39,
                y: rect.minY + rect.height * 0.492
            )
        )
        path.closeSubpath()
        return path
    }
}

#Preview("Crest Sky Plane Shape") {
    CrestSkyPlaneShape()
        .fill(.blue)
        .frame(width: 96, height: 96)
        .padding()
}
