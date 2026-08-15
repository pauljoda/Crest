import SwiftUI

struct CrestChromeButtonSurface: ViewModifier {
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
