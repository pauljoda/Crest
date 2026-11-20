import SwiftUI

/// Appearance only; selection, promotion and drag owners remain on the row.
///
/// Pins rest on the device's material, as the address field does. A selected
/// tab or pin is a sheet of Crest's light paper laid over the sidebar; a selected
/// pin keeps its accent edge as well.
struct BrowserTabAppearanceSurface: ViewModifier {
    let appearance: BrowserTabAppearance
    let accent: Color
    let isPinned: Bool
    let isSelected: Bool
    let isHovering: Bool
    var selectionEmphasis = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.sidebarLayerDepth) private var depth

    func body(content: Content) -> some View {
        let radius = BrowserSidebarMetrics.layerCornerRadius(depth: depth)
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
                    selectedBorderColor: selectedBorder(showsBorder: showsBorder),
                    selectedBorderWidth: isPinned ? CrestLayout.pinnedAccentBorderWidth : 1,
                    customSelectedFill: fill > 0 && !reduceTransparency ? accent.opacity(fill * 0.5) : nil,
                    // Hover keeps its standard weight; the setting only decides how much of
                    // the accent is in it, from the neutral hover to the accent itself.
                    customHoverFill: hover > 0 && !reduceTransparency
                        ? Color.primary.mix(with: accent, by: hover).opacity(CrestOpacity.hover) : nil,
                    customRestingFill: isPinned && fill > 0 && !reduceTransparency ? accent.opacity(fill * 0.2) : nil,
                    restingBorderColor: showsBorder ? accent : .clear,
                    selectsOnPaper: true)
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

    /// A selected pin's edge is its accent, as is a selected row's where the
    /// person outlines selected tabs or colors every tab's border. Otherwise
    /// the paper's own edge and shadow set a selected row apart, with a
    /// hairline only where more contrast is asked for.
    private func selectedBorder(showsBorder: Bool) -> Color {
        if isPinned || appearance.outlinesSelectedTabs || showsBorder { return accent }
        return contrast == .increased ? CrestColor.selectedBorder : .clear
    }
}
