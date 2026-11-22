import SwiftUI

struct BrowserCommandPaletteRowButtonStyle: ButtonStyle {
    let isSelected: Bool
    /// The color the selected row is tinted in, or nil for the plain paper
    /// the sidebar's selected tab is.
    var accent: Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, BrowserCommandPaletteMetrics.rowHorizontalPadding)
            .frame(minHeight: BrowserCommandPaletteMetrics.resultRowHeight)
            .contentShape(.rect)
            .modifier(BrowserCommandPaletteRowSurface(isSelected: isSelected, accent: accent))
    }
}
