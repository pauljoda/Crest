import Foundation

enum BrowserManualSetupSitePolicy {
    static func addedSuggestionTab(
        _ suggestion: BrowserSetupSiteSuggestion,
        in draft: BrowserManualSetupSpaceDraft
    ) -> BrowserTab? {
        draft.addedTabs.first { matches($0.url, suggestion.url) }
    }

    static func containsSuggestion(
        _ suggestion: BrowserSetupSiteSuggestion,
        in tabs: [BrowserTab]
    ) -> Bool {
        tabs.contains { matches($0.url, suggestion.url) }
    }

    static func manuallyAddedTabs(
        in draft: BrowserManualSetupSpaceDraft
    ) -> [BrowserTab] {
        draft.addedTabs.filter { tab in
            !BrowserSetupSiteSuggestion.popular.contains { suggestion in
                matches(tab.url, suggestion.url)
            }
        }
    }

    private static func matches(_ lhs: URL?, _ rhs: URL?) -> Bool {
        guard let lhs = lhs?.host(percentEncoded: false)?.lowercased(),
            let rhs = rhs?.host(percentEncoded: false)?.lowercased()
        else { return false }
        return normalized(lhs) == normalized(rhs)
    }

    private static func normalized(_ host: String) -> Substring {
        host.hasPrefix("www.") ? host.dropFirst(4) : host[...]
    }
}
