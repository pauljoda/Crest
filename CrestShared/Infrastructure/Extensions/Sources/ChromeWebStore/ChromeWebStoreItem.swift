import Foundation

struct BrowserChromeWebStoreItem: Equatable, Identifiable, Sendable {
    let id: BrowserChromeExtensionID
    let slug: String
    let storeURL: URL

    init?(url: URL) {
        guard url.scheme?.lowercased() == "https",
            url.host?.lowercased() == "chromewebstore.google.com",
            url.port == nil,
            url.user == nil,
            url.password == nil
        else {
            return nil
        }
        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count == 3,
            components[0] == "detail",
            !components[1].isEmpty,
            let extensionID = BrowserChromeExtensionID(components[2])
        else {
            return nil
        }
        var canonical = URLComponents()
        canonical.scheme = "https"
        canonical.host = "chromewebstore.google.com"
        canonical.path = "/detail/\(components[1])/\(extensionID.rawValue)"
        guard let storeURL = canonical.url else { return nil }
        id = extensionID
        slug = components[1]
        self.storeURL = storeURL
    }
}
