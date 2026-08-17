import SwiftUI

/// Geometry shared by selected, pressed, and hovered browser surfaces.
enum CrestInteractiveSurfaceMetrics {
    static let defaultSelectedBorderWidth: CGFloat = 0.5
    static let increasedContrastBorderWidth: CGFloat = 1.5
    static let selectedShadowRadius: CGFloat = 2
    static let selectedShadowYOffset: CGFloat = 1
}

struct CrestInteractiveSurfaceModifier: ViewModifier {
    let isSelected: Bool
    let isHovering: Bool
    let cornerRadius: CGFloat
    let isPressed: Bool
    let showsRestingSurface: Bool
    let selectedBorderColor: Color
    let selectedBorderWidth: CGFloat

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(
            cornerRadius: cornerRadius,
            style: .continuous
        )
        let isEmphasized = isSelected || isPressed

        content
            .background(fill, in: shape)
            .overlay {
                shape
                    .strokeBorder(
                        isEmphasized ? selectedBorderColor : .clear,
                        lineWidth: borderWidth
                    )
                    .allowsHitTesting(false)
            }
            .shadow(
                color: .black.opacity(shadowOpacity),
                radius: isEmphasized
                    ? CrestInteractiveSurfaceMetrics.selectedShadowRadius
                    : 0,
                y: isEmphasized
                    ? CrestInteractiveSurfaceMetrics.selectedShadowYOffset
                    : 0
            )
            .animation(accessibleSurfaceAnimation, value: isHovering)
            .animation(accessibleSurfaceAnimation, value: isEmphasized)
    }

    private var fill: Color {
        switch (isSelected || isPressed, isHovering, showsRestingSurface) {
        case (true, _, _):
            CrestColor.selectedSurface
        case (false, true, _):
            CrestColor.hover
        case (false, false, true):
            CrestColor.chromeSurface
        case (false, false, false):
            .clear
        }
    }

    private var borderWidth: CGFloat {
        guard contrast == .increased else { return selectedBorderWidth }
        return max(
            CrestInteractiveSurfaceMetrics.increasedContrastBorderWidth,
            selectedBorderWidth
        )
    }

    private var shadowOpacity: Double {
        guard isSelected || isPressed, !reduceTransparency else { return 0 }
        return CrestOpacity.interactionSelectionShadow
    }

    private var accessibleSurfaceAnimation: Animation? {
        BrowserVisualAccessibilityPolicy.animation(
            CrestMotion.surface,
            reduceMotion: reduceMotion
        )
    }
}

/// Owns pointer hover state for controls that use Crest's shared interaction
/// surface but do not otherwise need to react to hover themselves.
private struct CrestHoverSurfaceModifier: ViewModifier {
    let isSelected: Bool
    let cornerRadius: CGFloat
    let isPressed: Bool
    let showsRestingSurface: Bool
    let selectedBorderColor: Color
    let selectedBorderWidth: CGFloat

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .crestInteractiveSurface(
                isSelected: isSelected,
                isHovering: isHovering && isEnabled,
                cornerRadius: cornerRadius,
                isPressed: isPressed && isEnabled,
                showsRestingSurface: showsRestingSurface,
                selectedBorderColor: selectedBorderColor,
                selectedBorderWidth: selectedBorderWidth
            )
            .onHover { isHovering = $0 }
    }
}

extension View {
    func crestInteractiveSurface(
        isSelected: Bool,
        isHovering: Bool,
        cornerRadius: CGFloat = CrestRadius.compact,
        isPressed: Bool = false,
        showsRestingSurface: Bool = false,
        selectedBorderColor: Color = CrestColor.selectedBorder,
        selectedBorderWidth: CGFloat =
            CrestInteractiveSurfaceMetrics.defaultSelectedBorderWidth
    ) -> some View {
        modifier(
            CrestInteractiveSurfaceModifier(
                isSelected: isSelected,
                isHovering: isHovering,
                cornerRadius: cornerRadius,
                isPressed: isPressed,
                showsRestingSurface: showsRestingSurface,
                selectedBorderColor: selectedBorderColor,
                selectedBorderWidth: selectedBorderWidth
            )
        )
    }

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
