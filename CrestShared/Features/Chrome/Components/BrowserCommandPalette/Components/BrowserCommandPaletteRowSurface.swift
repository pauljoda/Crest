import SwiftUI

/// A palette row's surface: a faint plate at rest, and the selected row
/// lifted as the sidebar lifts its selected tab, or tinted in the Space's
/// accent where the person chose it.
struct BrowserCommandPaletteRowSurface: ViewModifier {
    // MARK: - Variables

    let isSelected: Bool
    /// The Space's accent the selected row is tinted in, or nil for the
    /// sidebar's lift.
    let accent: Color?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // MARK: - Actions - Drawing

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: BrowserCommandPaletteMetrics.rowCornerRadius)
        content
            .background {
                if !isSelected {
                    shape.fill(Color.primary.opacity(BrowserCommandPaletteMetrics.restingRowOpacity))
                }
            }
            .modifier(
                CrestInteractiveSurfaceModifier(
                    isSelected: isSelected, isHovering: false,
                    cornerRadius: BrowserCommandPaletteMetrics.rowCornerRadius, isPressed: false,
                    showsRestingSurface: false, selectedBorderColor: selectedBorder, selectedBorderWidth: 1,
                    customSelectedFill: selectedFill)
            )
    }

    // MARK: - Actions - Reading

    /// The accent over the lifted surface, or the lift a selected row's dark
    /// glass takes in the sidebar.
    private var selectedFill: Color? {
        if let accent, !reduceTransparency {
            return accent.opacity(BrowserCommandPaletteMetrics.selectedRowOpacity)
        }
        return colorScheme == .dark ? Color.white.opacity(CrestOpacity.darkSelectionLift) : nil
    }

    /// The selected row's edge: the accent where the row wears it, else
    /// brighter over dark glass, as the sidebar's selected tab has it.
    private var selectedBorder: Color {
        if let accent { return accent.opacity(BrowserCommandPaletteMetrics.selectedRowBorderOpacity) }
        return colorScheme == .dark ? Color.white.opacity(CrestOpacity.darkSelectionBorder) : CrestColor.selectedBorder
    }
}
