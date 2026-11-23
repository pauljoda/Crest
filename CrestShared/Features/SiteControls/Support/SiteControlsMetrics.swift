import SwiftUI

/// The geometry and type Site Controls take in the shell that shows them: a
/// compact popover under the pointer, or a sheet a finger works.
struct SiteControlsMetrics {
    // MARK: - Static Variables

    /// The popover on the Mac, and on an iPad wide enough for one.
    static let popover = SiteControlsMetrics(
        width: 320, padding: CrestSpacing.medium, sectionSpacing: 6, faviconSize: 28, actionTileHeight: 46,
        actionGlyphSize: 16, tileSpacing: 6, extensionTileHeight: 34, waitingHeight: 44, toggleHeight: 34,
        toggleColumns: 2, rowHeight: 32, rowInset: 3, glyphSize: 15, chipHeight: 24, glassIconSize: 28,
        glassIconGlyphSize: 12, sectionHeight: 16, keepsRootHeight: true,
        sectionFont: CrestTypography.label, titleFont: CrestTypography.label, detailFont: .system(size: 11),
        rowFont: .system(size: 13), valueFont: .system(size: 12), tileFont: .system(size: 11, weight: .medium),
        pageTitleFont: CrestTypography.label)

    /// The sheet on iPhone, and on an iPad too narrow for a popover.
    static let sheet = SiteControlsMetrics(
        width: nil, padding: 14, sectionSpacing: CrestSpacing.medium, faviconSize: 40, actionTileHeight: 66,
        actionGlyphSize: 21, tileSpacing: CrestSpacing.small, extensionTileHeight: 44, waitingHeight: 58,
        toggleHeight: 60, toggleColumns: 3, rowHeight: 48, rowInset: 4, glyphSize: 19, chipHeight: 30,
        glassIconSize: 44, glassIconGlyphSize: 17, sectionHeight: 22,
        keepsRootHeight: false, sectionFont: .headline, titleFont: .headline, detailFont: .footnote, rowFont: .body,
        valueFont: .callout, tileFont: .caption.weight(.medium), pageTitleFont: .headline)

    // MARK: - Variables

    /// The popover's width, or nil for a sheet's, which takes the screen's.
    let width: CGFloat?
    let padding: CGFloat
    let sectionSpacing: CGFloat
    let faviconSize: CGFloat
    let actionTileHeight: CGFloat
    let actionGlyphSize: CGFloat
    let tileSpacing: CGFloat
    let extensionTileHeight: CGFloat
    let waitingHeight: CGFloat
    let toggleHeight: CGFloat
    let toggleColumns: Int
    /// A row's height, its hover surface's too.
    let rowHeight: CGFloat
    /// The room inside a row above and below its content.
    let rowInset: CGFloat
    let glyphSize: CGFloat
    let chipHeight: CGFloat
    /// A round glass button at a page's corner, such as Back or Done, and
    /// its symbol.
    let glassIconSize: CGFloat
    let glassIconGlyphSize: CGFloat
    /// A section label's line, which its text button may stand a little
    /// taller than.
    let sectionHeight: CGFloat
    /// Whether a page keeps the root's height, so a popover never resizes.
    let keepsRootHeight: Bool
    /// A section's label and a text button such as Edit or Manage, alike.
    let sectionFont: Font
    let titleFont: Font
    let detailFont: Font
    let rowFont: Font
    let valueFont: Font
    let tileFont: Font
    /// A page's title over its rows.
    let pageTitleFont: Font
}

extension EnvironmentValues {
    /// The metrics of the shell showing Site Controls.
    @Entry var siteControlsMetrics = SiteControlsMetrics.popover
}
