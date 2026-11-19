import CoreGraphics

/// Controlled corner radii, from a compact control to the rounded band of a
/// large brand surface.
enum CrestRadius {
    static let compact: CGFloat = 8
    static let control: CGFloat = 12
    static let card: CGFloat = 16
    static let panel: CGFloat = 24
    static let band: CGFloat = 48
}
