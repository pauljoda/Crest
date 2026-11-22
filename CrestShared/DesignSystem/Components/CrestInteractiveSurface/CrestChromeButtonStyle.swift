import SwiftUI

/// Shared hover and press treatment for compact browser chrome controls.
struct CrestChromeButtonStyle: ButtonStyle {
    // MARK: - Variables

    /// The control's fixed size, or `nil` for a tile that takes the size its
    /// label and container give it.
    var controlSize: CGSize? = CGSize(
        width: CrestLayout.minimumHitTarget,
        height: CrestLayout.minimumHitTarget
    )
    var cornerRadius = CrestLayout.sidebarControlCornerRadius
    /// Draws a fixed fill at rest, for a tile that stands on its own rather
    /// than a glyph that only shows a surface under the pointer. It is a fill
    /// rather than the device's material because these tiles sit inside
    /// panels that already wear it, where material on material disappears.
    var showsRestingFill = false
    /// Draws the device's material at rest, for a control that floats on its
    /// own over the sidebar, as the pins and the address field stand on it.
    var restsOnMaterial = false
    /// Draws the surface of a control that is on, for a toggle.
    var isSelected = false
    /// Lays a control that is on, or pressed, on Crest's light paper, as the
    /// sidebar's selected tab is, rather than on the material.
    var selectsOnPaper = false
    /// How far past its surface the control takes presses on every side, for
    /// a small control that still needs a full hit target.
    var hitOutset: CGFloat = 0
    /// The color the control's glyph and title draw in while it is enabled,
    /// for a control that leads its group, or nil for the text's own color.
    var tint: Color? = nil

    // MARK: - Actions - Shapes

    /// A round control `diameter` across, such as a glyph on a card or the
    /// control that clears a field, taking presses `hitOutset` past its edge.
    static func circle(
        diameter: CGFloat = CrestLayout.minimumHitTarget,
        showsRestingFill: Bool = false,
        hitOutset: CGFloat = 0
    ) -> CrestChromeButtonStyle {
        CrestChromeButtonStyle(
            controlSize: CGSize(width: diameter, height: diameter),
            cornerRadius: diameter / 2,
            showsRestingFill: showsRestingFill,
            hitOutset: hitOutset
        )
    }

    // MARK: - Actions - Drawing

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(
                CrestChromeButtonSurface(
                    isPressed: configuration.isPressed,
                    controlSize: controlSize,
                    cornerRadius: cornerRadius,
                    showsRestingFill: showsRestingFill,
                    restsOnMaterial: restsOnMaterial,
                    isSelected: isSelected,
                    selectsOnPaper: selectsOnPaper,
                    hitOutset: hitOutset,
                    tint: tint
                )
            )
    }
}

private struct CrestChromeButtonSurface: ViewModifier {
    let isPressed: Bool
    let controlSize: CGSize?
    let cornerRadius: CGFloat
    let showsRestingFill: Bool
    let restsOnMaterial: Bool
    let isSelected: Bool
    let selectsOnPaper: Bool
    let hitOutset: CGFloat
    let tint: Color?

    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content
            .foregroundStyle(
                isEnabled
                    ? tint ?? Color.primary
                    : Color.secondary.opacity(CrestOpacity.disabled)
            )
            .frame(width: controlSize?.width, height: controlSize?.height)
            .contentShape(.rect)
            .crestHoverSurface(
                isSelected: isSelected,
                cornerRadius: cornerRadius,
                isPressed: isPressed,
                showsRestingSurface: restsOnMaterial,
                selectsOnPaper: selectsOnPaper
            )
            .background {
                if showsRestingFill {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(.quaternary)
                }
            }
            .padding(hitOutset)
            .contentShape(.rect)
    }
}
