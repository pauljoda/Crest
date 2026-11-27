import Foundation

/// The sections of the Tabs settings page.
///
/// New, pinned and saved tabs, switching, Tidy and sidebar widgets.
extension BrowserSettingsSection {
    static let newTabs = BrowserSettingsSection(
        name: "newTabs", title: "New tabs",
        searchTerms:
            "switch focus tabs opened from links Shift follow tabs moved to another Space move between Spaces open new tabs at position current folder Command-click middle-click"
    )
    static let durableTabs = BrowserSettingsSection(
        name: "durableTabs", title: "Pinned and saved tabs",
        searchTerms: "pinned saved close resume restore root URL favicon unload unloading return")
    static let splitFocus = BrowserSettingsSection(
        name: "splitFocus", title: "Split View",
        searchTerms: "Split View focus follows pointer mouse")
    static let recentTabs = BrowserSettingsSection(
        name: "recentTabs", title: "Switching",
        searchTerms: "recent tabs switcher switching Control-Tab")
    static let tidy = BrowserSettingsSection(
        name: "tidy", title: "Tidy",
        searchTerms: "Tidy organize sort open tabs into groups by topic Apple Intelligence")
    static let sidebarWidgets = BrowserSettingsSection(
        name: "sidebarWidgets", title: "Sidebar widgets",
        searchTerms: "sidebar widgets Now Playing media cards")
}
