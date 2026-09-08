import Foundation

enum BrowserChromeWebStoreInstallNavigation {
    static let scheme = BrowserExtensionInstallScheme.rawValue
    private static let host = "chrome-web-store"

    static func url(for extensionID: BrowserChromeExtensionID) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = "/\(extensionID.rawValue)"
        guard let url = components.url else {
            preconditionFailure("The fixed extension install URL is invalid.")
        }
        return url
    }

    static func item(
        for navigationURL: URL?,
        currentURL: URL?
    ) -> BrowserChromeWebStoreItem? {
        guard let navigationURL,
            navigationURL.scheme?.lowercased() == scheme,
            navigationURL.host?.lowercased() == host,
            navigationURL.port == nil,
            navigationURL.user == nil,
            navigationURL.password == nil,
            navigationURL.query == nil,
            navigationURL.fragment == nil,
            let currentItem = currentURL.flatMap(
                BrowserChromeWebStoreItem.init(url:)
            )
        else { return nil }
        let path = navigationURL.pathComponents.filter { $0 != "/" }
        guard path.count == 1,
            let requestedID = BrowserChromeExtensionID(path[0]),
            requestedID == currentItem.id
        else { return nil }
        return currentItem
    }
}
