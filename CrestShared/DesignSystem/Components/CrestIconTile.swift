import SwiftUI

/// A reusable colored symbol tile for navigation, settings, and feature identity.
struct CrestIconTile: View {
    let systemImage: String
    let color: Color
    var size: CGFloat = 30
    var symbolSize: CGFloat = 14
    var cornerRadius: CGFloat = CrestRadius.compact
    var castsShadow = false

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: symbolSize, weight: .semibold))
            .browserReadableForeground(over: color)
            .frame(width: size, height: size)
            .background(color, in: .rect(cornerRadius: cornerRadius))
            .shadow(
                color: color.opacity(castsShadow && !reduceTransparency ? 0.2 : 0),
                radius: castsShadow ? 5 : 0,
                y: castsShadow ? CrestSpacing.extraExtraSmall : 0
            )
    }
}
