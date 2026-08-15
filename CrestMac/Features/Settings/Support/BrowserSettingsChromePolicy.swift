import CoreGraphics

enum BrowserSettingsChromePolicy {
    static let usesNavigationSplitView = true
    static let usesResizableDesktopSplitView = true
    static let usesDedicatedResizableWindowScene = true
    static let permitsUserWindowResizing = true
    static let minimumContentSize = CGSize(width: 840, height: 610)
    static let defaultContentSize = CGSize(width: 900, height: 660)
    static let detailMinimumWidth: CGFloat = 600
    static let usesNativeSidebarToggle = true
    static let showsSelectionInWindowTitle = false
    static let showsStandardWindowControls = true
    static let toolbarHeight: CGFloat = 38
    /// The window name assistive technology uses to find Settings. The
    /// titlebar hides it, so it survives only if the window keeps its title.
    static let windowTitle = "Crest Settings"
}
