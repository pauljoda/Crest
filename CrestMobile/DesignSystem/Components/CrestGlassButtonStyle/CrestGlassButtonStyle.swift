import SwiftUI

/// A glyph control on Liquid Glass, which answers a finger or the pointer by
/// bending under it, so the control draws no surface of its own: the
/// floating controls of a phone's toolbar. A control standing alone wears
/// its own circle of glass; controls that share one piece, as Back and
/// Forward share a capsule, leave the glass to their group, which wears
/// `crestInteractiveGlass(in:)`.
struct CrestGlassButtonStyle: ButtonStyle {
    // MARK: - Variables

    var diameter = CrestLayout.glassIconButtonDiameter
    /// Whether the control stands on glass of its own, rather than on its
    /// group's.
    var wearsGlass = true

    // MARK: - Actions - Drawing

    func makeBody(configuration: Configuration) -> some View {
        CrestGlassButtonSurface(label: configuration.label, diameter: diameter, wearsGlass: wearsGlass)
    }
}

private struct CrestGlassButtonSurface: View {
    // MARK: - Variables

    let label: ButtonStyleConfiguration.Label
    let diameter: CGFloat
    let wearsGlass: Bool

    @Environment(\.isEnabled) private var isEnabled

    // MARK: - Actions - Drawing

    var body: some View {
        label
            .foregroundStyle(
                isEnabled ? Color.primary : Color.secondary.opacity(CrestOpacity.disabledGlyph)
            )
            .frame(width: diameter, height: diameter)
            .contentShape(.circle)
            .glassEffect(wearsGlass ? .regular.interactive() : .identity, in: .circle)
    }
}

extension View {
    /// Lays the view on Liquid Glass that answers a finger or the pointer, for
    /// a group of controls that share one piece of it, or a chip that is a
    /// control of its own.
    func crestInteractiveGlass(in shape: some Shape) -> some View {
        glassEffect(.regular.interactive(), in: shape)
    }
}

#if DEBUG
    #Preview("Alone and grouped") {
        HStack {
            Button("Tabs", systemImage: "square.on.square") {}
                .labelStyle(.iconOnly)
                .buttonStyle(CrestGlassButtonStyle())
            HStack(spacing: 0) {
                Button("Back", systemImage: "chevron.left") {}
                    .buttonStyle(CrestGlassButtonStyle(wearsGlass: false))
                Button("Forward", systemImage: "chevron.right") {}
                    .buttonStyle(CrestGlassButtonStyle(wearsGlass: false))
                    .disabled(true)
            }
            .labelStyle(.iconOnly)
            .crestInteractiveGlass(in: .capsule)
        }
        .padding()
    }
#endif
