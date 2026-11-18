import SwiftUI

/// The frosted body of the steps' pane: light glass over a light room and
/// dark glass over a dark one, fading from one to the other as the room
/// changes rather than switching at once.
struct BrowserSetupGlassPane<Shape: InsettableShape>: View {
    // MARK: - Variables

    let shape: Shape
    /// Whether the room reads light or dark.
    let scheme: ColorScheme

    // MARK: - Actions - Drawing

    var body: some View {
        ZStack {
            frost(.light)
            frost(.dark)
        }
        .allowsHitTesting(false)
    }

    private func frost(_ frostScheme: ColorScheme) -> some View {
        shape
            .fill(.regularMaterial)
            .environment(\.colorScheme, frostScheme)
            .opacity(scheme == frostScheme ? 1 : 0)
    }
}

/// The edge of a pane of glass floating over the room: a rim that catches
/// the light along its top and leading edges and fades around the far side,
/// a fainter line just inside it for the glass's thickness, a sheen across
/// its top, and a dark hairline where it meets the room.
struct BrowserSetupGlassEdge<Shape: InsettableShape>: View {
    // MARK: - Variables

    let shape: Shape
    /// Whether the room reads light or dark.
    let scheme: ColorScheme

    private var isDark: Bool { scheme == .dark }

    // MARK: - Actions - Drawing

    var body: some View {
        ZStack {
            shape.fill(
                LinearGradient(
                    colors: [.white.opacity(isDark ? 0.07 : 0.28), .white.opacity(0)],
                    startPoint: .top, endPoint: BrowserSetupGlassEdgeMetrics.sheenEnd))
            shape.inset(by: BrowserSetupGlassEdgeMetrics.thickness)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(isDark ? 0.16 : 0.45), .white.opacity(0.02), .white.opacity(0.1)],
                        startPoint: .top, endPoint: .bottom),
                    lineWidth: 1
                )
                .blur(radius: BrowserSetupGlassEdgeMetrics.thicknessBlur)
            shape.strokeBorder(rim, lineWidth: 1)
            shape.stroke(.black.opacity(isDark ? 0.5 : 0.12), lineWidth: BrowserSetupGlassEdgeMetrics.contact)
        }
        .allowsHitTesting(false)
    }

    /// Bright where the light falls on the edge, top and leading, fading
    /// across the pane and brightening a little again at the far corner.
    private var rim: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .white.opacity(isDark ? 0.62 : 0.95), location: 0),
                .init(color: .white.opacity(isDark ? 0.16 : 0.5), location: 0.3),
                .init(color: .white.opacity(isDark ? 0.05 : 0.25), location: 0.65),
                .init(color: .white.opacity(isDark ? 0.24 : 0.6), location: 1),
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

enum BrowserSetupGlassEdgeMetrics {
    /// Where the sheen across the top has faded away.
    static let sheenEnd = UnitPoint(x: 0.5, y: 0.22)
    /// How far inside the rim the line for the glass's thickness runs.
    static let thickness: CGFloat = 1.5
    static let thicknessBlur: CGFloat = 0.6
    /// The hairline where the pane meets the room, half outside its edge.
    static let contact: CGFloat = 0.5
}
