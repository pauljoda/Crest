import Foundation

/// The sections of the Appearance settings page.
///
/// The window, tabs, address field, zoom and app icon.
extension BrowserSettingsSection {
    static let addressBar = BrowserSettingsSection(
        name: "addressBar", title: "Address bar",
        searchTerms: "address bar toolbar position layout")
    static let spaceIcons = BrowserSettingsSection(
        name: "spaceIcons", title: "Space icons",
        searchTerms: "Space icons fit size sidebar automatic")
    static let windowAppearance = BrowserSettingsSection(
        name: "windowAppearance", title: "Appearance",
        searchTerms:
            "look and feel theme light dark accent color transparency sidebar left right borderless window full screen fullscreen show sidebar on hover switching Spaces interface"
    )
    static let pageZoom = BrowserSettingsSection(
        name: "pageZoom", title: "Page",
        searchTerms: "default page zoom percentage scale")
    static let tabAppearance = BrowserSettingsSection(
        name: "tabAppearance", title: "Tabs and pins",
        searchTerms:
            "tabs pins corner radius spacing padding density pin layout balanced rows stretch color borders accent outline selected tint"
    )
    static let tabStatus = BrowserSettingsSection(
        name: "tabStatus", title: "Tab status",
        searchTerms: "tab status badge replace icon audio visualizer")
    static let addressAppearance = BrowserSettingsSection(
        name: "addressAppearance", title: "Address field",
        searchTerms:
            "address field two lines one line site only accent outline editing animate command palette copy URL button Super Copy"
    )
    static let folderAppearance = BrowserSettingsSection(
        name: "folderAppearance", title: "Folders",
        searchTerms: "folders icon only tint folder title highlights tab counts color borders")
    static let groupAppearance = BrowserSettingsSection(
        name: "groupAppearance", title: "Groups",
        searchTerms: "groups tint group name highlights tab counts color borders")
    static let hoverPreviews = BrowserSettingsSection(
        name: "hoverPreviews", title: "Hover previews",
        searchTerms: "hover preview tabs folders cards")
    static let appIcon = BrowserSettingsSection(
        name: "appIcon", title: "App icon",
        searchTerms: "app icon Dock alternate icon")
    static let moreCustomization = BrowserSettingsSection(
        name: "moreCustomization", title: "More Customization",
        searchTerms: "more customization animation motion fine tuning")
    static let resetAppearance = BrowserSettingsSection(
        name: "resetAppearance", title: "Reset",
        searchTerms: "reset appearance defaults")
}
