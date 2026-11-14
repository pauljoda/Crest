import SwiftUI

/// How a preview card grows out of its row: from a point at the card's edge
/// beside the row, it scales up to its full size.
struct BrowserTabPreviewGrowth: GeometryEffect {
    // MARK: - Static Variables

    /// How large the card starts, as a share of its full size.
    private static let startingScale: CGFloat = 0.2

    // MARK: - Variables

    /// How far grown the card is, from 0 (its starting size) to 1 (its full
    /// size).
    var progress: CGFloat
    /// The point the card grows from, in the card's points.
    let anchor: CGPoint
    /// Where the card is drawn in the layer, which the growth works around.
    let origin: CGSize

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    // MARK: - Actions - Growing

    func effectValue(size: CGSize) -> ProjectionTransform {
        guard progress < 1 else { return ProjectionTransform() }
        let scale = Self.startingScale + (1 - Self.startingScale) * max(progress, 0)
        let point = CGPoint(x: origin.width + anchor.x, y: origin.height + anchor.y)
        return ProjectionTransform(
            CGAffineTransform(translationX: -point.x, y: -point.y)
                .concatenating(CGAffineTransform(scaleX: scale, y: scale))
                .concatenating(CGAffineTransform(translationX: point.x, y: point.y)))
    }
}
