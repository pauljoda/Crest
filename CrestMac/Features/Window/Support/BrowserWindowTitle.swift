import Foundation

/// Native window metadata shares the address bar's host formatting, but never
/// falls back to credentials, a local file path, or a URL's query and fragment.
@MainActor
enum BrowserWindowTitle {
    static func resolve(
        page: BrowserPage?,
        storedTitle: String? = nil,
        url: URL?,
        fallback: String = ProductIdentity.name
    ) -> String {
        guard let page else {
            return resolve(title: storedTitle, url: url, fallback: fallback)
        }
        let title =
            page.pendingNavigationURL == nil && page.navigationFailure == nil
            ? page.title : nil
        return resolve(title: title, url: page.displayURL ?? url, fallback: fallback)
    }

    private static func resolve(title: String?, url: URL?, fallback: String) -> String {
        if let title = BrowserTab.resolvedCustomTitle(title) { return title }
        guard let url, let host = url.host(), !host.isEmpty else { return fallback }
        return BrowserAddressPresentation(url.absoluteString).domain
    }
}
