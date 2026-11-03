import SwiftUI

/// What a look shows of itself before any Space wears it: a template's look
/// in the look's own sidebar mode and icon style, as the core gives them to
/// the Spaces setup makes.
extension SetupLook {
    // MARK: - Static Variables

    /// The template every look's preview starts from.
    private static let previewHouse = SpaceHouse.winter

    // MARK: - Variables

    /// The look on the template every preview starts from.
    var previewBranding: SpaceBranding { applying(to: Self.previewHouse.look) }

    /// The symbol a previewed Space wears, which an icon shows and a crest
    /// keeps for the places too small for it.
    var previewSymbol: String { "house.fill" }

    // MARK: - Actions - Looks

    /// `branding` in this look: the sidebar mode, gradient angle and icon
    /// style the core gives the look, keeping its colors and crest.
    func applying(to branding: SpaceBranding) -> SpaceBranding {
        var look = branding
        look.themeMode = themeMode
        look.gradientAngle = gradientAngle ?? branding.gradientAngle
        look.iconStyle = iconStyle
        return look.normalized()
    }
}
