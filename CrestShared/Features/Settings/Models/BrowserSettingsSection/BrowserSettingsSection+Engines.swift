import Foundation

/// The sections of the Engines settings page.
///
/// The default engine and per-site engine rules.
extension BrowserSettingsSection {
    static let defaultEngine = BrowserSettingsSection(
        name: "defaultEngine", title: "Default engine",
        searchTerms: "Chromium WebKit hybrid default browser engine recommended")
    static let engineRules = BrowserSettingsSection(
        name: "engineRules", title: "Website rules",
        searchTerms: "websites rules site engine protected video DRM compatibility add website rule")
}
