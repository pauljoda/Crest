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
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let radius = BrowserSidebarMetrics.layerCornerRadius(depth: depth)
        let selectedAccent = isPinned || appearance.outlinesSelectedTabs
        let showsBorder = appearance.borders == .all || (isPinned && appearance.borders == .pinned)
        // Each choice is read only where it shows, so a drag of the pin fill
        // or the hover tint re-renders the pins or the hovered row alone.
        let fill = isPinned ? BrowserTabAppearance.intensity(appearance.pinFill) : 0
        let hover = isHovering ? BrowserTabAppearance.intensity(appearance.hoverFill) : 0
        content
            .modifier(
                CrestInteractiveSurfaceModifier(
                    isSelected: isSelected, selectionEmphasis: selectionEmphasis,
                    isHovering: isHovering, cornerRadius: radius, isPressed: false,
                    showsRestingSurface: isPinned,
                    selectedBorderColor: selectedAccent ? accent : selectedBorder,
                    selectedBorderWidth: isPinned ? CrestLayout.pinnedAccentBorderWidth : 1,
                    customSelectedFill: isPinned
                        ? (fill > 0 && !reduceTransparency ? accent.opacity(fill * 0.5) : nil) : selectionLift,
                    // Hover keeps its standard weight; the setting only decides how much of
                    // the accent is in it, from the neutral hover to the accent itself.
                    customHoverFill: hover > 0 && !reduceTransparency
                        ? Color.primary.mix(with: accent, by: hover).opacity(CrestOpacity.hover) : nil,
                    customRestingFill: isPinned && fill > 0 && !reduceTransparency ? accent.opacity(fill * 0.2) : nil,
                    restingBorderColor: showsBorder ? accent : .clear)
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

    /// The lift a selected row's dark glass takes, which a pin's own plate
    /// and light glass need none of.
    private var selectionLift: Color? {
        colorScheme == .dark ? Color.white.opacity(CrestOpacity.darkSelectionLift) : nil
    }

    /// A selected row's edge: brighter over dark glass, where the standard
    /// hairline disappears into a dark sidebar.
    private var selectedBorder: Color {
        guard !isPinned, colorScheme == .dark else { return CrestColor.selectedBorder }
        return Color.white.opacity(CrestOpacity.darkSelectionBorder)
    }
}
