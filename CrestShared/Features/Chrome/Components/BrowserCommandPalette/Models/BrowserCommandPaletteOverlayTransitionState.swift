import CoreGraphics

struct BrowserCommandPaletteOverlayTransitionState: Equatable, Sendable {
    let opacity: Double
    let scale: CGFloat

    static let hidden = Self(opacity: 0, scale: 1)
    static let presented = Self(opacity: 1, scale: 1)
}
