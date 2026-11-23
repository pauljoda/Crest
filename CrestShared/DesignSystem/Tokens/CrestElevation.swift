import SwiftUI

/// How far a surface stands off what lies under it, drawn as the shadow it
/// casts: the shadow's color and opacity, how soft it is, where it falls, and
/// whether it stays when the person reduces transparency. A surface that
/// floats over the page turns opaque then and keeps only its edge, so its
/// shadow goes with the translucency.
///
/// Cast one with `crestElevation(_:)`.
struct CrestElevation: Hashable, Sendable {
    // MARK: - Static Variables

    /// A control standing just off its ground, such as the primary button's
    /// pill, a setup step at rest or an icon tile.
    static let control = CrestElevation(color: CrestBrandPalette.ink, opacity: 0.18, radius: 2, y: 1)
    /// A small item held above its ground, such as a Space being reordered,
    /// the setup step that is open, or a download on its way to its list.
    static let lifted = CrestElevation(opacity: 0.25, radius: 4, y: 2)
    /// A handle on a color track or dial, standing off the color under it.
    static let handle = CrestElevation(opacity: 0.3, radius: 3, y: 1)
    /// A handle the person is holding.
    static let heldHandle = CrestElevation(opacity: 0.4, radius: 6, y: 3)
    /// A card resting in the sidebar, such as a widget.
    static let card = CrestElevation(opacity: 0.16, radius: 8, y: 3)
    /// A panel, flyout, bar or notice floating over the page or the canvas
    /// under it.
    static let panel = CrestElevation(opacity: 0.16, radius: 14, y: 6, staysUnderReducedTransparency: false)
    /// An item the person drags.
    static let dragged = CrestElevation(opacity: 0.22, radius: 10, y: 5)
    /// The page card, lifted off the window around it.
    static let page = CrestElevation(opacity: 0.11, radius: 7, y: 2, staysUnderReducedTransparency: false)
    /// A page floating over the whole window, such as a Peek.
    static let floatingPage = CrestElevation(
        opacity: 0.32, radius: 24, y: 12, staysUnderReducedTransparency: false)
    /// The sidebar floating over the page while it is hidden, its shadow
    /// falling across the page beside it.
    static let floatingSidebar = CrestElevation(
        opacity: 0.3, radius: 28, x: 8, y: 8, staysUnderReducedTransparency: false)
    /// A window shown on its own over the room, such as setup's live window.
    static let window = CrestElevation(color: CrestBrandPalette.ink, opacity: 0.42, radius: 30, y: 18)

    // MARK: - Variables

    let color: Color
    let opacity: Double
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
    /// Whether the shadow stays when the person reduces transparency.
    let staysUnderReducedTransparency: Bool

    // MARK: - Initializers

    private init(
        color: Color = .black,
        opacity: Double,
        radius: CGFloat,
        x: CGFloat = 0,
        y: CGFloat,
        staysUnderReducedTransparency: Bool = true
    ) {
        self.color = color
        self.opacity = opacity
        self.radius = radius
        self.x = x
        self.y = y
        self.staysUnderReducedTransparency = staysUnderReducedTransparency
    }

    // MARK: - Actions - Drawing

    /// The shadow's color, at `scale` of its strength, or clear where
    /// reduced transparency takes it away.
    func shadowColor(scale: Double, reducingTransparency: Bool) -> Color {
        let isShown = staysUnderReducedTransparency || !reducingTransparency
        return color.opacity(isShown ? opacity * scale : 0)
    }
}
