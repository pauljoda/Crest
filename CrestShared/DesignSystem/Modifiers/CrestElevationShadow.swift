import SwiftUI

/// Casts an elevation's shadow, taking it away where the elevation does not
/// stay under reduced transparency.
private struct CrestElevationShadow: ViewModifier {
    // MARK: - Variables

    let elevation: CrestElevation?
    let scale: Double

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // MARK: - Actions - Drawing

    /// One shadow whether or not there is an elevation, so lifting and
    /// settling keeps the view's identity and animates between the two.
    func body(content: Content) -> some View {
        content.shadow(
            color: elevation?.shadowColor(scale: scale, reducingTransparency: reduceTransparency) ?? .clear,
            radius: elevation?.radius ?? 0,
            x: elevation?.x ?? 0,
            y: elevation?.y ?? 0
        )
    }
}

extension View {
    /// Casts `elevation`'s shadow at `scale` of its strength, or none when
    /// `elevation` is nil, so a surface that lifts and settles moves between
    /// its shadow and none.
    func crestElevation(_ elevation: CrestElevation?, scale: Double = 1) -> some View {
        modifier(CrestElevationShadow(elevation: elevation, scale: scale))
    }
}
