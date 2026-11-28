import Foundation

/// The sections of the Shortcuts settings page.
///
/// The keyboard commands page, which draws its own list.
extension BrowserSettingsSection {
    static let keyboardShortcuts = BrowserSettingsSection(
        name: "keyboardShortcuts", title: "Keyboard shortcuts",
        searchTerms: "keyboard keys commands rebind remap hotkeys navigation tabs Spaces page")
}
