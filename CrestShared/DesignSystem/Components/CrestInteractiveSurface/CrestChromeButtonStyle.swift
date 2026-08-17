import SwiftUI

/// Shared hover and press treatment for compact browser chrome controls.
struct CrestChromeButtonStyle: ButtonStyle {
    var controlSize = CGSize(
        width: CrestLayout.minimumHitTarget,
        height: CrestLayout.minimumHitTarget
    )
    var cornerRadius = CrestLayout.sidebarControlCornerRadius

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(
                CrestChromeButtonSurface(
                    isPressed: configuration.isPressed,
                    controlSize: controlSize,
                    cornerRadius: cornerRadius
                )
            )
    }
}

private struct CrestChromeButtonSurface: ViewModifier {
    let isPressed: Bool
    let controlSize: CGSize
    let cornerRadius: CGFloat

    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content
            .foregroundStyle(
                isEnabled
                    ? Color.primary
                    : Color.secondary.opacity(CrestOpacity.disabled)
            )
            .frame(width: controlSize.width, height: controlSize.height)
            .contentShape(.rect)
            .crestHoverSurface(
                isSelected: false,
                cornerRadius: cornerRadius,
                isPressed: isPressed
            )
    }
}
