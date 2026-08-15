import CoreGraphics

enum BrowserSettingsVisualPolicy {
    static let sidebarMinimumWidth: CGFloat = 224
    static let sidebarIdealWidth: CGFloat = 236
    static let sidebarMaximumWidth: CGFloat = 260
    static let sidebarIconSize: CGFloat = 24
    static let sidebarRowMinimumHeight: CGFloat = 34
    static let showsSidebarSubtitles = false
    static let usesConciseNavigationLabels = true
    static let usesSidebarAtmosphere = false
    static let usesNativeSearchFields = true
    static let centersPageIdentity = true
    /// A pane's identity wears the destination's brand hue, not a grey wash.
    static let usesMonochromePageIdentity = false
    /// A pane names itself in the display serif over its subtitle, through the one
    /// shared `BrowserSettingsPaneHeader` both shells draw.
    static let usesEditorialPageIdentity = true
    /// A selected sidebar row wears the destination's hue rather than system blue,
    /// inside the platform's own selection shape.
    static let usesBrandSelectionTint = true
    static let reservesProminenceForPrimaryActions = true
    static let hidesResolvedPrimaryActions = true
    static let pageIconSize: CGFloat = 48
    static let maximumReadableContentWidth: CGFloat = 700
}
