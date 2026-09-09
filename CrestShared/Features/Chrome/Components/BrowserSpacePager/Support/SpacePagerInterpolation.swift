import CoreGraphics

/// The same fractional Space coordinate drives every presentation leaf.
struct SpacePagerInterpolation {
    let lower: Int
    let upper: Int
    let fraction: CGFloat

    init?(position: CGFloat, count: Int) {
        guard count > 0, position.isFinite else { return nil }
        let position = min(CGFloat(count - 1), max(0, position))
        lower = Int(position.rounded(.down))
        upper = min(count - 1, lower + 1)
        fraction = position - CGFloat(lower)
    }

    func frame(from start: CGRect, to end: CGRect) -> CGRect {
        CGRect(
            x: start.minX + (end.minX - start.minX) * fraction,
            y: start.minY + (end.minY - start.minY) * fraction,
            width: start.width + (end.width - start.width) * fraction,
            height: start.height + (end.height - start.height) * fraction)
    }

    static func backdropOpacity(at position: CGFloat, index: Int) -> Float {
        Float(min(1, max(0, position - CGFloat(index) + 1)))
    }
}
