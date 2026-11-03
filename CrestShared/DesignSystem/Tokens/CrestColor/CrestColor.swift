import SwiftUI

/// Semantic colors for Crest-authored chrome. Space identity colors remain data-driven.
enum CrestColor {
    static let selection = Color.primary.opacity(CrestOpacity.selection)
    static let chromeSurface = Color.primary.opacity(CrestOpacity.chromeSurface)
    static let hover = Color.primary.opacity(CrestOpacity.hover)
    static let subtleBorder = Color.primary.opacity(CrestOpacity.border)
    static let selectedBorder = Color.primary.opacity(CrestOpacity.selectedBorder)
    static let dropIndicator = CrestBrandPalette.paper.opacity(CrestOpacity.dropIndicator)
    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary

    /// The platform's own window background, under a Space's colors.
    #if os(macOS)
        static let windowBackground = Color(nsColor: .windowBackgroundColor)
    #else
        static let windowBackground = Color(uiColor: .systemBackground)
    #endif

    // MARK: - Status

    // The house tinctures ember, gold and sage, darkened in light and lifted
    // in dark until each reads as text at 4.5:1 or more on the window, form,
    // grouped-list and paper surfaces Crest draws in either appearance. Dark
    // danger also keeps 3:1 under a white glyph, as a remove button draws it.

    /// Something failed, was refused or is unsafe.
    static let danger = status(
        light: CrestColorComponents(red: 178, green: 50, blue: 37),
        dark: CrestColorComponents(red: 238, green: 106, blue: 92))
    /// Something needs the person: a decision, a fix, or a caution to read.
    static let warning = status(
        light: CrestColorComponents(red: 138, green: 90, blue: 8),
        dark: CrestColorComponents(red: 236, green: 190, blue: 92))
    /// Something is settled and fine: allowed, secure, ready.
    static let success = status(
        light: CrestColorComponents(red: 47, green: 112, blue: 66),
        dark: CrestColorComponents(red: 134, green: 196, blue: 142))
    /// The wash under a row or tag that is in danger.
    static let dangerFill = danger.opacity(CrestOpacity.statusFill)
    /// The wash under a row or tag that needs the person.
    static let warningFill = warning.opacity(CrestOpacity.statusFill)

    private static func status(light: CrestColorComponents, dark: CrestColorComponents) -> Color {
        CrestPlatformDynamicColor.make(light: light, lightOpacity: 1, dark: dark, darkOpacity: 1)
    }
}
