import Foundation

enum BrowserHistoryURL {
    static func normalized(_ url: URL) -> URL? {
        #if CREST_CORE_BACKED
        return BrowserCorePolicy.normalizedHistoryURL(url)
        #else
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return nil
        }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.fragment = nil
        return components.url
        #endif
    }
}
