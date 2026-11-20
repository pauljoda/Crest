import SwiftUI

/// Shared hover and press treatment for compact browser chrome controls.
struct CrestChromeButtonStyle: ButtonStyle {
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
                    hitOutset: hitOutset
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

    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content
            .foregroundStyle(
                isEnabled
                    ? Color.primary
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
