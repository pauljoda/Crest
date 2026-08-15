import Foundation

enum BrowserExtensionExternalNavigationPolicy {
    static func shouldOpenInBrowserTab(
        currentURL: URL?,
        destinationURL: URL?,
        isTopLevel: Bool,
        isAppInitiated: Bool
    ) -> Bool {
        guard currentURL?.scheme?.lowercased() == "webkit-extension",
            let scheme = destinationURL?.scheme?.lowercased(),
            scheme == "http" || scheme == "https"
        else { return false }
        return isTopLevel && !isAppInitiated
    }
}
