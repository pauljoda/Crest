import SwiftUI

/// Appearance only; selection, promotion and drag owners remain on the row.
struct BrowserTabAppearanceSurface: ViewModifier {
    let appearance: BrowserTabAppearance
    let accent: Color
    let isPinned: Bool
    let isSelected: Bool
    let isHovering: Bool
    var selectionEmphasis = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.sidebarLayerDepth) private var depth
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let radius = BrowserSidebarMetrics.layerCornerRadius(depth: depth)
        let selectedRow = isSelected && !isPinned
        let showsBorder = appearance.borders == .all || (isPinned && appearance.borders == .pinned)
        let restingBorder: Color =
            selectedRow && contrast == .increased
            ? .primary : showsBorder || (selectedRow && appearance.outlinesSelectedTabs) ? accent : .clear
        // Each choice is read only where it shows, so a drag of the pin fill
        // or the hover tint re-renders the pins or the hovered row alone.
        let fill = isPinned ? BrowserTabAppearance.intensity(appearance.pinFill) : 0
        content
            .modifier(
                CrestInteractiveSurfaceModifier(
                    isSelected: isPinned && isSelected, selectionEmphasis: selectionEmphasis,
                    isHovering: isHovering || selectedRow, cornerRadius: radius, isPressed: false,
                    showsRestingSurface: isPinned,
                    selectedBorderColor: accent,
                    selectedBorderWidth: isPinned ? CrestLayout.pinnedAccentBorderWidth : 1,
                    customSelectedFill: isPinned
                        ? (fill > 0 && !reduceTransparency ? accent.opacity(fill * 0.5) : nil) : nil,
                    // Hover keeps its standard weight; the setting only decides how much of
                    // the accent is in it, from the neutral hover to the accent itself.
                    customHoverFill: isHovering || selectedRow
                        ? Self.hoverFill(
                            appearance: appearance, accent: accent, reduceTransparency: reduceTransparency,
                            opacity: selectedRow ? CrestOpacity.selection : CrestOpacity.hover)
                        : nil,
                    customRestingFill: isPinned && fill > 0 && !reduceTransparency ? accent.opacity(fill * 0.2) : nil,
                    restingBorderColor: restingBorder)
            )
            .background {
                if isSelected, appearance.pinGlow > 0, !reduceTransparency {
                    BrowserTabSelectionGlow(
                        cornerRadius: radius,
                        color: accent.opacity(BrowserTabAppearance.intensity(appearance.pinGlow) * 0.6)
                    )
                }
            }
    }

    static func hoverFill(
        appearance: BrowserTabAppearance, accent: Color, reduceTransparency: Bool, opacity: Double = CrestOpacity.hover
    ) -> Color {
        let hover = BrowserTabAppearance.intensity(appearance.hoverFill)
        return (hover > 0 && !reduceTransparency ? Color.primary.mix(with: accent, by: hover) : Color.primary)
            .opacity(opacity)
    }
}
