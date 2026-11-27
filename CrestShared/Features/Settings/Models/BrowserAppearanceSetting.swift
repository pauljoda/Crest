import Foundation

/// A row of Settings › Appearance: one of the choices that change how Crest
/// reads and behaves, which the page shows, or the fine tuning of fills,
/// borders and highlights, which waits in More Customization at its end.
enum BrowserAppearanceSetting: Hashable, Sendable, CaseIterable {
    case windowBorder
    case material
    case materialColor
    case sidebarOnRight
    /// Fitting Space icons to the sidebar, and their size when they are not.
    case spaceIconSize
    case followSpaceAccent
    case appearanceMode
    case darkSpaceDimming
    case spacePageMotion
    case sidebarRevealWidth
    case sidebarRevealDelay
    case sidebarSlideDuration
    case fullScreenSidebarReveal
    case spaceShortcutSidebarReveal
    case defaultPageZoom
    case cornerRadius
    case tabScale
    /// The room the sidebar keeps between its rows, bars and sections.
    case sidebarSpacing
    case pinLayout
    case pinsFillRow
    case colorBorders
    case selectedTabOutline
    /// Drawing the selected tab on white paper or on the material.
    case selectedTabStyle
    case selectedTabOpacity
    case selectedPinTint
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
    case commandPaletteAccent
    case addressDisplay
    case copyURLButton
    case superCopy
    case folderIconOnly
    case folderTintTitle
    case folderHighlights
    case folderTabCounts
    case folderBorders
    case groupTintTitle
    case groupHighlights
    case groupTabCounts
    case groupBorders
    case appIcon
    case tabHoverPreview
    case folderHoverPreview

    // MARK: - Static Variables

    /// The rows the page shows; More Customization holds the rest.
    static let onPage: Set<BrowserAppearanceSetting> = [
        .sidebarOnRight, .appearanceMode, .followSpaceAccent, .spacePageMotion, .sidebarRevealDelay,
        .sidebarSlideDuration, .fullScreenSidebarReveal, .spaceShortcutSidebarReveal, .defaultPageZoom, .cornerRadius,
        .tabScale, .sidebarSpacing,
        .pinLayout, .websitePinColors, .dimUnloadedTabs, .tabStatus, .addressDisplay, .commandPaletteAccent,
        .copyURLButton, .superCopy,
        .folderIconOnly, .folderTabCounts, .groupTabCounts, .appIcon, .tabHoverPreview, .folderHoverPreview,
    ]

    // MARK: - Variables

    /// Whether the page shows the row, rather than More Customization.
    var isOnPage: Bool { Self.onPage.contains(self) }
}
