import Foundation

/// The width a window's sidebar opens at when the window keeps none of its
/// own: the last width a window committed.
///
/// It is kept beside the window's other chrome choices, so an isolated launch
/// keeps it in its own preferences and never reads or changes the installed
/// app's.
@MainActor
enum BrowserRootSidebarWidthPersistence {
    static func read() -> CGFloat {
        BrowserSidebarWidthPreference.value(
            forKey: BrowserRootPreferenceKeys.sidebarWidth,
            default: BrowserChromeLayout.sidebarIdealWidth,
            defaults: BrowserChromeAppearancePreference.defaults
        )
    }

    static func write(_ width: Double) {
        BrowserChromeAppearancePreference.defaults.set(width, forKey: BrowserRootPreferenceKeys.sidebarWidth)
    }
}
