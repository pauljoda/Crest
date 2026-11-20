import SwiftUI

/// A palette row's surface: a faint plate at rest, and the selected row a
/// sheet of Crest's paper, as the sidebar's selected tab is, tinted in the
/// Space's accent where the person chose it.
struct BrowserCommandPaletteRowSurface: ViewModifier {
    // MARK: - Variables

    let isSelected: Bool
    /// The Space's accent the selected row is tinted in, or nil for plain
    /// paper.
    let accent: Color?

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

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
                    customSelectedFill: selectedFill, selectsOnPaper: true)
            )
    }

    // MARK: - Actions - Reading

    /// The accent over the paper, where the row wears it.
    private var selectedFill: Color? {
        guard let accent, !reduceTransparency else { return nil }
        return accent.opacity(BrowserCommandPaletteMetrics.selectedRowOpacity)
    }

    /// The selected row's edge: the accent where the row wears it, else the
    /// paper's own edge, with a hairline only where more contrast is asked
    /// for, as the sidebar's selected tab has it.
    private var selectedBorder: Color {
        if let accent { return accent.opacity(BrowserCommandPaletteMetrics.selectedRowBorderOpacity) }
        return contrast == .increased ? CrestColor.selectedBorder : .clear
    }
}
