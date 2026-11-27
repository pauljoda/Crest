import Foundation

/// The sections of the Privacy settings page and its Space pages.
///
/// System permissions on the Mac, and each Space's privacy.
extension BrowserSettingsSection {
    static let systemPermissions = BrowserSettingsSection(
        name: "systemPermissions", title: "System permissions",
        searchTerms:
            "system permissions access camera microphone location notifications passkeys files folders downloads allow blocked repair"
    )
    static let spacePrivacyPages = BrowserSettingsSection(
        name: "spacePrivacyPages", title: "Spaces",
        searchTerms: "each Space history site permissions privacy")
    static let privacySpace = BrowserSettingsSection(
        name: "privacySpace", title: "Space",
        searchTerms: "choose Space")
    static let spaceLock = BrowserSettingsSection(
        name: "spaceLock", title: "Lock",
        searchTerms: "lock Touch ID Face ID password private protect locks again background")
    static let dataRetention = BrowserSettingsSection(
        name: "dataRetention", title: "History",
        searchTerms: "history retention keep records archive downloads delete older records")
    static let sitePermissions = BrowserSettingsSection(
        name: "sitePermissions", title: "Site permissions",
        searchTerms:
            "site permissions camera microphone location notifications reset all",
        requiredCapability: .permissions
    )
    static let websiteData = BrowserSettingsSection(
        name: "websiteData", title: "Website data",
        searchTerms: "cookies website data cache storage remove signed out")
    static let clearBrowsingData = BrowserSettingsSection(
        name: "clearBrowsingData", title: "Clear browsing data",
        searchTerms: "clear browsing data history cache time range")
}
