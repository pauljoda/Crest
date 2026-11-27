import Foundation

/// The sections of the Advanced settings page.
///
/// Setup again, Feature Flags, and import and export.
extension BrowserSettingsSection {
    static let setup = BrowserSettingsSection(
        name: "setup", title: "Setup",
        searchTerms: "setup onboarding again")
    static let featureFlagsLink = BrowserSettingsSection(
        name: "featureFlagsLink", title: "Feature Flags",
        searchTerms: "feature flags experimental")
    static let dataPortability = BrowserSettingsSection(
        name: "dataPortability", title: "Import and export",
        searchTerms: "import export backup portability data records another browser")
}
