import SwiftUI

// MARK: - Types

extension EnvironmentValues {
    /// The color a tab's surface shows under its content, which an icon on it
    /// has to stand out from; nil outside a tab's surface.
    @Entry var browserTabSurfaceGround: Color? = nil
}

/// Appearance only; selection, promotion and drag owners remain on the row.
///
/// Pins rest on the device's material, as the address field does. A selected
/// tab or pin lies on what the person's selected tab style draws: a sheet of
/// Crest's white paper, which takes a pin's color where the person tints
/// selected pins, or a layer of the device's material. A selected pin keeps
/// its accent edge as well.
struct BrowserTabAppearanceSurface: ViewModifier {
    // MARK: - Variables

    let appearance: BrowserTabAppearance
    let accent: Color
    let isPinned: Bool
    let isSelected: Bool
    let isHovering: Bool
    var selectionEmphasis = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.deviceColorScheme) private var deviceColorScheme
    @Environment(\.sidebarLayerDepth) private var depth

    /// The scheme the device's material draws in here, whose glass a selection
    /// on the material lifts and edges, whatever scheme the surroundings read.
    private var materialScheme: ColorScheme {
        CrestSurfaceTone.shownScheme(over: colorScheme, window: deviceColorScheme)
    }

    // MARK: - Body

    func body(content: Content) -> some View {
        let radius = BrowserSidebarMetrics.layerCornerRadius(depth: depth)
        let showsBorder = appearance.borders == .all || (isPinned && appearance.borders == .pinned)
        // Each choice is read only where it shows, so a drag of the pin fill
        // or the hover tint re-renders the pins or the hovered row alone, and
        // a change to the selection's style only the selected tab and pin.
        let fill = isPinned ? BrowserTabAppearance.intensity(appearance.pinFill) : 0
        let hover = isHovering ? BrowserTabAppearance.intensity(appearance.hoverFill) : 0
        let style = isSelected ? appearance.selectedTabStyle : .standard
        content
            .environment(\.browserTabSurfaceGround, ground(style: style, fill: fill))
            .modifier(
                CrestInteractiveSurfaceModifier(
                    isSelected: isSelected, selectionEmphasis: selectionEmphasis,
                    isHovering: isHovering, cornerRadius: radius, isPressed: false,
                    showsRestingSurface: isPinned,
                    selectedBorderColor: selectedBorder(style: style, showsBorder: showsBorder),
                    selectedBorderWidth: isPinned ? CrestLayout.pinnedAccentBorderWidth : 1,
                    customSelectedFill: isSelected ? selectedFill(style: style, fill: fill) : nil,
                    // Hover keeps its standard weight; the setting only decides how much of
                    // the accent is in it, from the neutral hover to the accent itself.
                    customHoverFill: hover > 0 && !reduceTransparency
                        ? Color.primary.mix(with: accent, by: hover).opacity(CrestOpacity.hover) : nil,
                    customRestingFill: isPinned && fill > 0 && !reduceTransparency ? accent.opacity(fill * 0.2) : nil,
                    restingBorderColor: showsBorder ? accent : .clear,
                    selectionPaper: isSelected ? paper(style: style) : nil)
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

    // MARK: - Actions - Drawing

    /// The sheet a selection in `style` lies on, or nil on the material: as
    /// opaque as the person chose, or solid where transparency is reduced.
    /// Where the person tints selected pins, a pin's sheet lies over the pin's
    /// color, its site's or, with website colors off, its accent; otherwise
    /// over the pin as it rests, the white a selected tab is.
    private func paper(style: BrowserSelectedTabStyle) -> CrestPaperSheet? {
        // The opacity is read only where paper shows it.
        guard style.liesOnPaper else { return nil }
        return style.paper(
            opacity: reduceTransparency ? 1 : appearance.selectedTabOpacity,
            ground: isPinned && appearance.tintsSelectedPins ? accent : nil)
    }

    /// What a selection wears over its sheet. A pin wears its pinned fill's
    /// accent and, tinted on paper, a wash of its color as well; a row on the
    /// material, the lift dark glass takes.
    private func selectedFill(style: BrowserSelectedTabStyle, fill: Double) -> Color? {
        guard isPinned else {
            return !style.liesOnPaper && materialScheme == .dark ? CrestColor.darkSelectionLift : nil
        }
        return selectedPinTint(style: style, fill: fill).map { accent.opacity($0) }
    }

    /// How strongly a selected pin wears its accent over its sheet, or nil
    /// where it wears none.
    private func selectedPinTint(style: BrowserSelectedTabStyle, fill: Double) -> Double? {
        guard isPinned, !reduceTransparency else { return nil }
        let tint = style.liesOnPaper && appearance.tintsSelectedPins ? CrestOpacity.selectedPinTint : 0
        // Two washes of the one accent, laid one over the other.
        let strength = 1 - (1 - tint) * (1 - fill * 0.5)
        return strength > 0 ? strength : nil
    }

    /// The color the surface shows under its content, laid as the layers
    /// above draw it: the resting surface with its pin fill, and, selected,
    /// the sheet of paper over the pin's color or the material, with the
    /// accent washed over it, each laid over the one below as layers
    /// composite. The device's material takes its color from what lies
    /// behind it, so it counts as Crest's surface in the scheme the material
    /// draws in.
    private func ground(style: BrowserSelectedTabStyle, fill: Double) -> Color {
        let material = Self.surface(in: materialScheme)
        let resting =
            isPinned && fill > 0 && !reduceTransparency
            ? material.mix(with: accent, by: fill * 0.2, in: .device) : material
        guard isSelected else { return resting }
        var selected = material
        if let paper = paper(style: style) {
            selected = (paper.ground ?? resting).mix(with: Self.surface(in: .light), by: paper.opacity, in: .device)
        }
        guard let tint = selectedPinTint(style: style, fill: fill) else { return selected }
        return selected.mix(with: accent, by: tint, in: .device)
    }

    /// Crest's surface in `scheme`: paper in the light, charcoal in the dark.
    private static func surface(in scheme: ColorScheme) -> Color {
        (scheme == .dark ? CrestBrandTheme.surfaceDarkComponents : CrestBrandTheme.surfaceLightComponents).color
    }

    /// A selected pin's edge is its accent, as is a selected row's where the
    /// person outlines selected tabs. On paper a row's edge is its accent too
    /// where the person colors every tab's border, and otherwise the paper's
    /// own edge and shadow set it apart, with a hairline only where more
    /// contrast is asked for. On the material it is a hairline, brighter over
    /// dark glass, where the standard one disappears into a dark sidebar.
    private func selectedBorder(style: BrowserSelectedTabStyle, showsBorder: Bool) -> Color {
        if isPinned || appearance.outlinesSelectedTabs { return accent }
        guard style.liesOnPaper else {
            return materialScheme == .dark ? CrestColor.darkSelectionBorder : CrestColor.selectedBorder
        }
        if showsBorder { return accent }
        return contrast == .increased ? CrestColor.selectedBorder : .clear
    }
}
