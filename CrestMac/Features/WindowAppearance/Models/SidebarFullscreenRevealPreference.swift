import Foundation

/// Whether the sidebar hover area stays live while a page shows alone in full
/// screen, so the pointer at the window's edge floats the sidebar over it.
enum SidebarFullscreenRevealPreference {
    static let key = "crest.appearance.sidebar-fullscreen-reveal"
    static let defaultValue = false

    /// The stored choice, for code that has no view to read it through.
    @MainActor
    static var isEnabled: Bool {
        BrowserChromeAppearancePreference.defaults.object(forKey: key) as? Bool ?? defaultValue
    }
}
