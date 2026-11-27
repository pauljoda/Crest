import Foundation

/// The sections of the AdBlocking settings page.
///
/// The blocking level, filter lists, custom rules and exempt sites.
extension BrowserSettingsSection {
    static let adBlockingLevel = BrowserSettingsSection(
        name: "adBlockingLevel", title: "Blocking",
        searchTerms: "ads trackers content blocking level strict balanced off customized")
    static let filterLists = BrowserSettingsSection(
        name: "filterLists", title: "Filter lists",
        searchTerms: "filter lists EasyList uBlock AdGuard cookie notices update now")
    static let customFilterLists = BrowserSettingsSection(
        name: "customFilterLists", title: "Your Lists",
        searchTerms: "subscribe custom filter lists address URL add list")
    static let customFilters = BrowserSettingsSection(
        name: "customFilters", title: "My Filters",
        searchTerms: "my filters custom rules block element")
    static let blockingSites = BrowserSettingsSection(
        name: "blockingSites", title: "Sites with Blocking Off",
        searchTerms: "sites allowlist exceptions turn on blocking")
}
