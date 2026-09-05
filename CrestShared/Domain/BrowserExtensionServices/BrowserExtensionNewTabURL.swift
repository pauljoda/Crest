import Foundation

/// Chrome packages explicitly request this internal URL when creating tabs.
/// Crest represents its own start page with no navigation URL.
enum BrowserExtensionNewTabURL {
    static func resolve(_ url: URL?) -> URL? {
        guard let url,
            url.scheme?.lowercased() == "chrome",
            url.host?.lowercased() == "newtab",
            url.path.isEmpty || url.path == "/",
            url.user == nil, url.password == nil, url.port == nil
        else { return url }
        return nil
    }
}
