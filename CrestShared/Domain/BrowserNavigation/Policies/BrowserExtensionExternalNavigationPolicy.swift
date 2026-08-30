import Foundation

enum BrowserExtensionExternalNavigationPolicy {
    static func shouldReplaceCurrentTabRuntime(
        currentURL: URL?,
        destinationURL: URL?,
        isTopLevel: Bool,
        isAppInitiated: Bool
    ) -> Bool {
        guard let currentScheme = currentURL?.scheme?.lowercased(),
            ["chrome-extension", "crest-extension", "webkit-extension"]
                .contains(currentScheme),
            let scheme = destinationURL?.scheme?.lowercased(),
            scheme == "http" || scheme == "https"
        else { return false }
        return isTopLevel && !isAppInitiated
    }
}
