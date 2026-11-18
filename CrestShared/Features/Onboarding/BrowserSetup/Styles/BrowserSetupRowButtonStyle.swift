import SwiftUI

/// A setup row that opens a page or chooses something, with the design
/// system's hover and press surface reaching out past the row's content so
/// it frames the whole row while the row's text stays in line with the rest
/// of the form.
struct BrowserSetupRowButtonStyle: ButtonStyle {
    // MARK: - Static Variables

    /// How far the surface reaches past the row's content on each side.
    static let reach: CGFloat = 8

    // MARK: - Actions - Drawing

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, Self.reach)
            .padding(.vertical, Self.reach / 2)
            .contentShape(.rect)
            .crestHoverSurface(isPressed: configuration.isPressed)
            .padding(.horizontal, -Self.reach)
            .padding(.vertical, -Self.reach / 2)
    }
}

extension ButtonStyle where Self == BrowserSetupRowButtonStyle {
    static var browserSetupRow: BrowserSetupRowButtonStyle { BrowserSetupRowButtonStyle() }
}
