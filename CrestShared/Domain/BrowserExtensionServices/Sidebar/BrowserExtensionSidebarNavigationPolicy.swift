import Foundation

enum BrowserExtensionSidebarNavigationPolicy {
    enum Decision: Equatable { case allow, openTab, cancel }

    static func decide(url: URL, extensionBaseURL: URL, isMainFrame: Bool, opensNewWindow: Bool) -> Decision {
        let ownOrigin =
            url.scheme == extensionBaseURL.scheme && url.host == extensionBaseURL.host
            && url.port == extensionBaseURL.port && url.user == nil && url.password == nil
        if ownOrigin { return opensNewWindow ? .openTab : .allow }
        if url.absoluteString == "about:blank" { return opensNewWindow ? .cancel : .allow }
        if ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            return isMainFrame || opensNewWindow ? .openTab : .allow
        }
        return .cancel
    }
}
