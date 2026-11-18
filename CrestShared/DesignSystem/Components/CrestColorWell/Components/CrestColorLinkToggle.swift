import SwiftUI

/// The link between a fill's colors, on or off at a glance: linked, a tile
/// in the controls' accent with the link in white or black as reads best,
/// where moving one color orbits the rest with it; unlinked, a plain tile
/// with the link in gray, where each color moves on its own.
struct CrestColorLinkToggle: View {
    // MARK: - Variables

    @Binding var isLinked: Bool

    // MARK: - Actions - Drawing

    var body: some View {
        Button(isLinked ? "Unlink Colors" : "Link Colors", systemImage: "link") {
            isLinked.toggle()
        }
        .labelStyle(.iconOnly)
        .buttonStyle(CrestColorLinkToggleStyle(isOn: isLinked))
        .help(isLinked ? Text("Unlink Colors") : Text("Link Colors"))
        .accessibilityValue(isLinked ? Text("Linked") : Text("Unlinked"))
        .accessibilityIdentifier("color-link")
    }
}

/// A tile filled in the controls' accent while on and plain while off, with
/// the hover and press every chrome control shares.
private struct CrestColorLinkToggleStyle: ButtonStyle {
    let isOn: Bool

    @Environment(\.crestControlAccent) private var controlAccent
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        let accent = controlAccent ?? CrestBrandTheme.accent
        return configuration.label
            .font(.system(size: CrestColorLinkToggleMetrics.glyph, weight: .semibold))
            .foregroundStyle(
                isOn ? AnyShapeStyle(accent.perceptualForeground(in: colorScheme)) : AnyShapeStyle(.secondary)
            )
            .frame(width: CrestColorPopoverMetrics.control.width, height: CrestColorPopoverMetrics.control.height)
            .background {
                RoundedRectangle(cornerRadius: CrestRadius.compact, style: .continuous)
                    .fill(isOn ? AnyShapeStyle(accent) : AnyShapeStyle(.quaternary))
            }
            .contentShape(.rect)
            .crestHoverSurface(cornerRadius: CrestRadius.compact, isPressed: configuration.isPressed)
    }
}

enum CrestColorLinkToggleMetrics {
    static let glyph: CGFloat = 13
}
