import CoreGraphics

/// The measured appearance of a drag preview part-way between two shapes.
struct BrowserTabDragPreviewMetrics: Equatable, Sendable {
    let width: CGFloat
    let height: CGFloat
    let titleOpacity: Double
    /// Corner radius of the preview's own surface.
    let cornerRadius: CGFloat
    /// `0` keeps the row's leading favicon at the leading edge, `1` centres it.
    let contentCentering: CGFloat
    /// Cross-fade weight between the row layout and the card's centred one.
    let cardContentWeight: CGFloat
}
