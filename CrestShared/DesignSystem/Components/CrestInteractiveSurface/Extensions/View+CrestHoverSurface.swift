import SwiftUI

extension View {
    func crestHoverSurface(
        isSelected: Bool = false,
        cornerRadius: CGFloat = CrestRadius.compact,
        isPressed: Bool = false,
        showsRestingSurface: Bool = false,
        selectedBorderColor: Color = CrestColor.selectedBorder,
        selectedBorderWidth: CGFloat =
            CrestInteractiveSurfaceMetrics.defaultSelectedBorderWidth
    ) -> some View {
        modifier(
            CrestHoverSurfaceModifier(
                isSelected: isSelected,
                cornerRadius: cornerRadius,
                isPressed: isPressed,
                showsRestingSurface: showsRestingSurface,
                selectedBorderColor: selectedBorderColor,
                selectedBorderWidth: selectedBorderWidth
            )
        )
    }
}
