import Foundation

/// The sections of the Spaces settings page and its Space pages.
///
/// A Space's appearance, browsing, downloads and deletion, and the touch Space list.
extension BrowserSettingsSection {
    static let crestStudio = BrowserSettingsSection(
        name: "crestStudio", title: "Crest Studio",
        searchTerms:
            "Crest Studio name icon emblem colors theme banner background sidebar pattern gradient accent profile identity intensity text color light dark automatic preview"
    )
    static let spaceList = BrowserSettingsSection(
        name: "spaceList", title: "Spaces",
        searchTerms: "Spaces order reorder add Sub-Space")
    static let spaceGroup = BrowserSettingsSection(
        name: "spaceGroup", title: "Group",
        searchTerms: "group crests Sub-Space")
    static let spaceCustomization = BrowserSettingsSection(
        name: "spaceCustomization", title: "Appearance",
        searchTerms: "name crest colors background appearance")
    static let spaceBrowsing = BrowserSettingsSection(
        name: "spaceBrowsing", title: "Browsing",
        searchTerms: "search engine suggestions archive tabs cleanup archive now search with isolation independence")
    static let spaceAutofill = BrowserSettingsSection(
        name: "spaceAutofill", title: "Passwords and Autofill",
        searchTerms: "passwords autofill")
    static let spaceSeparatePinnedTabs = BrowserSettingsSection(
        name: "spaceSeparatePinnedTabs", title: "Pinned tabs",
        searchTerms: "separate pinned tabs group")
    static let spaceDownloads = BrowserSettingsSection(
        name: "spaceDownloads", title: "Downloads",
        searchTerms: "downloads folder save location ask where to save choose folder")
    static let spaceDeletion = BrowserSettingsSection(
        name: "spaceDeletion", title: "Delete Space",
        searchTerms: "delete Space remove")
}
