import SwiftUI

/// One paper banner of Crest's mark: a rounded rectangle cut at its foot into
/// a soft swallowtail, drawn on the mark's 64-point grid and scaled to fill
/// the frame it is given.
struct CrestMarkBannerShape: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / CrestStartPageMarkMetrics.grid
        let point = { (x: CGFloat, y: CGFloat) in CGPoint(x: rect.minX + x * scale, y: rect.minY + y * scale) }
        var path = Path()
        path.move(to: point(17, 13.8))
        path.addQuadCurve(to: point(19.8, 11), control: point(17, 11))
        path.addLine(to: point(44.2, 11))
        path.addQuadCurve(to: point(47, 13.8), control: point(47, 11))
        path.addLine(to: point(47, 32.2))
        path.addQuadCurve(to: point(44.78, 33.3), control: point(47, 35))
        path.addLine(to: point(34.22, 25.2))
        path.addQuadCurve(to: point(29.78, 25.2), control: point(32, 23.5))
        path.addLine(to: point(19.22, 33.3))
        path.addQuadCurve(to: point(17, 32.2), control: point(17, 35))
        path.closeSubpath()
        return path
    }
}
