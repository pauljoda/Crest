import Foundation

/// Validates the private install navigation Crest's in-page AMO button emits.
///
/// The bridge cannot be trusted to name its own add-on: a page can synthesize
/// the same anchor for any slug. The requested slug therefore only resolves
/// when it matches the add-on page the web view is actually displaying.
enum BrowserMozillaAddonsInstallNavigation {
    static let scheme = BrowserExtensionInstallScheme.rawValue

    private static let host = "mozilla-addons"

    static func url(for slug: BrowserMozillaAddonSlug) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = "/\(slug.rawValue)"
        guard let url = components.url else {
            preconditionFailure("The fixed add-on install URL is invalid.")
        }
        return url
    }

    static func item(
        for navigationURL: URL?,
        currentURL: URL?
    ) -> BrowserMozillaAddonsItem? {
        guard let navigationURL,
            navigationURL.scheme?.lowercased() == scheme,
            navigationURL.host?.lowercased() == host,
            navigationURL.port == nil,
            navigationURL.user == nil,
            navigationURL.password == nil,
            navigationURL.query == nil,
            navigationURL.fragment == nil,
            let currentItem = currentURL.flatMap(
                BrowserMozillaAddonsItem.init(url:)
            )
        else { return nil }
        let path = navigationURL.pathComponents.filter { $0 != "/" }
        guard path.count == 1,
            let requestedSlug = BrowserMozillaAddonSlug(path[0]),
            requestedSlug == currentItem.slug
        else { return nil }
        return currentItem
    }
}
