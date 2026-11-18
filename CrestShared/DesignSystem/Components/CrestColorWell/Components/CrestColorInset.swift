import SwiftUI

extension View {
    /// Sets this color surface into the popover in `shape`, as if pressed
    /// below it, with nothing drawn over the colors themselves: a ring round
    /// it shaded like the walls of a recess, dark under its top edge and
    /// catching light at its bottom, and a fine dark edge where the colors
    /// begin.
    func crestColorInset<S: InsettableShape>(_ shape: S, rim: CGFloat = CrestColorInsetMetrics.rim) -> some View {
        modifier(CrestColorInset(shape: shape, rim: rim))
    }
}

/// The recess a color wheel or a color slider's track sits in, drawn all
/// outside it, so the colors show exactly as they are.
private struct CrestColorInset<S: InsettableShape>: ViewModifier {
    let shape: S
    /// How wide the ring round the surface is.
    let rim: CGFloat

    func body(content: Content) -> some View {
        content
            .clipShape(shape)
            .background {
                // The recess's walls, a ring round the surface.
                shape
                    .inset(by: -rim)
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: .black.opacity(CrestColorInsetMetrics.shade), location: 0),
                                .init(color: .black.opacity(CrestColorInsetMetrics.shade * 0.35), location: 0.55),
                                .init(color: .white.opacity(CrestColorInsetMetrics.light), location: 1),
                            ],
                            startPoint: .top, endPoint: .bottom)
                    )
                    .allowsHitTesting(false)
            }
            .overlay {
                // The edge where the colors begin, just outside them.
                shape
                    .inset(by: -CrestLayout.hairline)
                    .strokeBorder(.black.opacity(CrestColorInsetMetrics.edge), lineWidth: CrestLayout.hairline)
                    .allowsHitTesting(false)
            }
    }
}

enum CrestColorInsetMetrics {
    static let rim: CGFloat = 4
    /// How dark the ring is under the top edge, how much light it catches
    /// at the bottom, and how dark the edge round the colors is.
    static let shade = 0.32
    static let light = 0.22
    static let edge = 0.35
}
