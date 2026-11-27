import Foundation

/// The sections of the Search settings page.
///
/// The default search, the command palette and search providers.
extension BrowserSettingsSection {
    static let defaultSearch = BrowserSettingsSection(
        name: "defaultSearch", title: "Default search",
        searchTerms: "search engine Google default private windows suggestions Tab Space search providers")
    static let paletteResults = BrowserSettingsSection(
        name: "paletteResults", title: "Results",
        searchTerms:
            "command palette address bar layout top hit prefer open tabs match reasons results order sections blended also show reset order"
    )
    static let paletteTyping = BrowserSettingsSection(
        name: "paletteTyping", title: "Typing",
        searchTerms:
            "sites before search complete addresses inline autocomplete learn from my choices clear learned choices calculator paste and go"
    )
    static let searchProviders = BrowserSettingsSection(
        name: "searchProviders", title: "Search providers",
        searchTerms:
            "site searches providers shortcuts keywords YouTube Wikipedia scopes add provider restore defaults"
    )
}
