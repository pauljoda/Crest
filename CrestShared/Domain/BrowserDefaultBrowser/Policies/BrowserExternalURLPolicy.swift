import Foundation

enum BrowserExternalURLPolicy {
    static func accepts(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return false }
        return url.host(percentEncoded: false)?.isEmpty == false
    }
}
