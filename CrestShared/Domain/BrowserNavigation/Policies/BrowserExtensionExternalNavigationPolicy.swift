import Foundation

enum BrowserExtensionExternalNavigationPolicy {
    static func shouldOpenInBrowserTab(
        currentURL: URL?,
        destinationURL: URL?,
        isTopLevel: Bool,
        isAppInitiated: Bool
    ) -> Bool {
        guard let currentScheme = currentURL?.scheme?.lowercased(),
            currentScheme == "webkit-extension" || currentScheme == "crest-extension",
            let scheme = destinationURL?.scheme?.lowercased(),
            scheme == "http" || scheme == "https"
        else { return false }
        return isTopLevel && !isAppInitiated
    }
}
