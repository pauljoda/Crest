import Foundation

/// The sections of the Links settings page.
///
/// Where links from outside a page open, Quick Window, Peek and routes.
extension BrowserSettingsSection {
    static let externalLinks = BrowserSettingsSection(
        name: "externalLinks", title: "Links from other apps",
        searchTerms: "external apps open in Space default links")
    static let quickWindow = BrowserSettingsSection(
        name: "quickWindow", title: "Quick Window",
        searchTerms: "Quick Window auto-archive remember the chosen Space for each site")
    static let peek = BrowserSettingsSection(
        name: "peek", title: "Peek",
        searchTerms: "Peek cross-site links pinned saved open with modifier drag links dim page size speed test")
    static let linkRouting = BrowserSettingsSection(
        name: "linkRouting", title: "Routing",
        searchTerms: "routes routing rules sites open in Space new route")
}
