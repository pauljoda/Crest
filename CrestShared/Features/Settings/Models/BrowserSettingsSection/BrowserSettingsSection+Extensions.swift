import Foundation

/// The sections of the Extensions settings page and its Space pages.
///
/// A Space's extensions and the engine's extension tools.
extension BrowserSettingsSection {
    static let extensionsSpace = BrowserSettingsSection(
        name: "extensionsSpace", title: "Space",
        searchTerms: "choose Space", requiredCapability: .extensions)
    static let installedExtensions = BrowserSettingsSection(
        name: "installedExtensions", title: "Extensions",
        searchTerms:
            "extensions add-ons Chrome Web Store install remove installed Chromium extension manager shortcuts permissions copies",
        requiredCapability: .extensions
    )
}
