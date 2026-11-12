import Foundation

/// A row of Settings › Appearance that a customization style can leave out of
/// the page, for Advanced at its end.
enum BrowserAppearanceSetting: Hashable, Sendable, CaseIterable {
    case windowBorder
    case material
    case sidebarOnRight
    /// Fitting Space icons to the sidebar, and their size when they are not.
    case spaceIconSize
    case followSpaceAccent
    case appearanceMode
    case darkSpaceDimming
    case spacePageMotion
    case sidebarRevealWidth
    case fullScreenSidebarReveal
    case defaultPageZoom
    case cornerRadius
    case tabScale
    case pinLayout
    case pinsFillRow
    case colorBorders
    case selectedTabOutline
    case websitePinColors
    case dimUnloadedTabs
    case pinnedFill
    case selectedTabGlow
    case hoverTint
    case tabStatus
    case audioVisualizer
    case addressFill
    case addressBorder
    case addressEditingOutline
    case commandPaletteMotion
    case addressDisplay
    case copyURLButton
    case superCopy
    case folderIconOnly
    case folderTintTitle
    case folderHighlights
    case folderTabCounts
    case folderBorders
    case appIcon
}
