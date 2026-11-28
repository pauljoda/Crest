import Foundation

/// The sections of the About settings page.
///
/// The version, updates, what's new and community links.
extension BrowserSettingsSection {
    static let version = BrowserSettingsSection(
        name: "version", title: "Version",
        searchTerms: "version build bundle identifier")
    static let softwareUpdates = BrowserSettingsSection(
        name: "softwareUpdates", title: "Software updates",
        searchTerms: "updates update channel check for updates automatically download install")
    static let whatsNew = BrowserSettingsSection(
        name: "whatsNew", title: "What's New",
        searchTerms: "what's new changelog release notes")
    static let community = BrowserSettingsSection(
        name: "community", title: "Community and support",
        searchTerms: "feedback Reddit GitHub issues report roadmap support community")
}
