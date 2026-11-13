import Foundation

/// Whether a hidden sidebar floats over the page for a moment when a shortcut
/// moves the window to another Space, so the person sees where they landed.
enum SidebarSpaceShortcutRevealPreference {
    static let key = "crest.appearance.sidebar-space-shortcut-reveal"
    static let defaultValue = false

    /// The stored choice, for code that has no view to read it through.
    @MainActor
    static var isEnabled: Bool {
        BrowserChromeAppearancePreference.defaults.object(forKey: key) as? Bool ?? defaultValue
    }
}
