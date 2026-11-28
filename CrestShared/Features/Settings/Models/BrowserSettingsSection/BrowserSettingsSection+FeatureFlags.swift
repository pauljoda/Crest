import Foundation

/// The sections of the FeatureFlags settings page.
///
/// The engine experiments page, which draws its own list.
extension BrowserSettingsSection {
    static let engineFeatureFlags = BrowserSettingsSection(
        name: "engineFeatureFlags", title: "Feature Flags",
        searchTerms:
            "WebKit Chromium experimental preview testable developer stable runtime flags features",
        requiredCapability: .featureFlags
    )
}
