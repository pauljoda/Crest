import SwiftUI

/// A form row that opens a page or chooses something, with the design
/// system's hover and press surface reaching out past the row's content so
/// it frames the whole row while the row's text stays in line with the rest
/// of the form. A row that stands for what is shown, as a settings list's
/// row stands for its page, wears the selected surface while it does.
struct CrestFormRowButtonStyle: ButtonStyle {
    // MARK: - Static Variables

    /// How far the surface reaches past the row's content on each side.
    static let reach: CGFloat = 8

    // MARK: - Variables

    var isSelected = false
    var cornerRadius = CrestRadius.compact

    // MARK: - Actions - Drawing

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, Self.reach)
            .padding(.vertical, Self.reach / 2)
            .contentShape(.rect)
            .crestHoverSurface(isSelected: isSelected, cornerRadius: cornerRadius, isPressed: configuration.isPressed)
            .padding(.horizontal, -Self.reach)
            .padding(.vertical, -Self.reach / 2)
    }
}

extension ButtonStyle where Self == CrestFormRowButtonStyle {
    static var crestFormRow: CrestFormRowButtonStyle { CrestFormRowButtonStyle() }
}
