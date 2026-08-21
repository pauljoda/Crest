import Foundation
import WebKit

@MainActor
enum BrowserPageConfiguration {
    /// Builds the configuration every Crest page shares.
    ///
    /// `preferredContentMode` and `decorate` are the two seams a platform shell
    /// needs: macOS asks sites for their desktop presentation while mobile takes
    /// the recommended one, and `decorate` runs last so a platform can add its own
    /// media policy, content scripts, and bridges — or override a shared default —
    /// without hand-rolling a second configuration that drifts from this one.
    static func make(
        for profile: BrowsingProfile,
        websiteDataStore: WKWebsiteDataStore? = nil,
        webExtensionController: WKWebExtensionController? = nil,
        contentRuleList: WKContentRuleList? = nil,
        contentRuleLists: [WKContentRuleList] = [],
        preferredContentMode: WKWebpagePreferences.ContentMode = .desktop,
        decorate: @MainActor (WKWebViewConfiguration) -> Void = { _ in }
    ) -> WKWebViewConfiguration {
        let webpagePreferences = WKWebpagePreferences()
        webpagePreferences.preferredContentMode = preferredContentMode
        webpagePreferences.allowsContentJavaScript = true

        let preferences = WKPreferences()
        preferences.isElementFullscreenEnabled = true
        // WebKit can distinguish a user-activated `window.open()` from an
        // unsolicited automatic window. Keep automatic windows blocked by
        // default; each page enables them only for an explicitly allowed site.
        // User-activated new tabs and windows are unaffected by this setting.
        preferences.javaScriptCanOpenWindowsAutomatically = false
        // Resident background tabs stay alive for instant host swaps, while
        // WebKit suspends their JavaScript and layout when detached from a window.
        preferences.inactiveSchedulingPolicy = .suspend
        #if os(macOS)
            BrowserWebKitFeatureFlagStore.active.apply(to: preferences)
        #endif

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore =
            websiteDataStore
            ?? BrowserWebsiteDataStore.launchScoped(for: profile)
        configuration.webExtensionController = webExtensionController
        configuration.defaultWebpagePreferences = webpagePreferences
        configuration.preferences = preferences
        configuration.applicationNameForUserAgent = safariCompatibleApplicationName
        configuration.upgradeKnownHostsToHTTPS = true
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.suppressesIncrementalRendering = false
        configuration.limitsNavigationsToAppBoundDomains = false
        for ruleList in contentRuleLists {
            configuration.userContentController.add(ruleList)
        }
        if let contentRuleList,
            !contentRuleLists.contains(where: { $0 === contentRuleList })
        {
            configuration.userContentController.add(contentRuleList)
        }
        decorate(configuration)
        return configuration
    }

    static var safariCompatibleApplicationName: String {
        let operatingSystemMajorVersion = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        // WKWebView omits Safari's browser tokens. Supply the platform's native
        // compatibility suffix without an app token so sign-in providers evaluate
        // Crest as the user-driven browser it is instead of an embedded app flow.
        return BrowserPlatformUserAgent.applicationName(
            operatingSystemMajorVersion: operatingSystemMajorVersion
        )
    }
}
