import SwiftUI

struct CrestFieldSurface: ViewModifier {
    // MARK: - Variables

    /// Whether the field inside the row has focus, as the row's owner tracks
    /// it.
    let isFocused: Bool
    /// The least height the row takes.
    let minHeight: CGFloat

    @Environment(\.crestFieldSurfaceRole) private var role
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: CrestFieldMetrics.cornerRadius,
            style: .continuous
        )
    }

    // MARK: - Actions - Drawing

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, CrestFieldMetrics.horizontalPadding)
            .frame(minHeight: minHeight)
            .background(role.fill, in: shape)
            .overlay {
                shape.strokeBorder(
                    role.border,
                    lineWidth: CrestFieldMetrics.borderWidth
                )
            }
            .overlay {
                RoundedRectangle(
                    cornerRadius: CrestFieldMetrics.cornerRadius
                        + CrestFieldMetrics.focusRingWidth / 2,
                    style: .continuous
                )
                .strokeBorder(
                    CrestBrandTheme.accent.opacity(CrestFieldMetrics.focusRingOpacity),
                    lineWidth: CrestFieldMetrics.focusRingWidth
                )
                .padding(-CrestFieldMetrics.focusRingWidth / 2)
                .opacity(isFocused ? 1 : 0)
                .allowsHitTesting(false)
            }
            .animation(
                CrestMotion.press.unlessReducingMotion(reduceMotion),
                value: isFocused
            )
    }
}
