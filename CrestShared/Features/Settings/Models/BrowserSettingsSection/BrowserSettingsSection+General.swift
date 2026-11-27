import Foundation

/// The sections of the General settings page.
///
/// Startup, browsing and the Mac's webpage, video and quitting choices.
extension BrowserSettingsSection {
    static let defaultBrowser = BrowserSettingsSection(
        name: "defaultBrowser", title: "Default browser",
        searchTerms: "default browser make Crest the default check again")
    static let startup = BrowserSettingsSection(
        name: "startup", title: "Startup",
        searchTerms: "startup when Crest opens launch restore start on new tab default Space")
    static let floatingSidebar = BrowserSettingsSection(
        name: "floatingSidebar", title: "Sidebar",
        searchTerms: "floating sidebar allow")
    static let translation = BrowserSettingsSection(
        name: "translation", title: "Translation",
        searchTerms:
            "translate pages automatically languages download offer translation",
        requiredCapability: .translation
    )
    static let webpages = BrowserSettingsSection(
        name: "webpages", title: "Webpages",
        searchTerms: "spelling spell check check spelling typing text editing")
    static let pictureInPicture = BrowserSettingsSection(
        name: "pictureInPicture", title: "Picture in Picture",
        searchTerms: "video floating border corners switching tabs apps leaving desktop return video")
    static let developerToolbar = BrowserSettingsSection(
        name: "developerToolbar", title: "Developer",
        searchTerms: "developer toolbar localhost local pages")
    static let quitting = BrowserSettingsSection(
        name: "quitting", title: "Quitting",
        searchTerms: "ask before quitting quit confirm")
}
