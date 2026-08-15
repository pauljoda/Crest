import Foundation

enum BrowserSiteCertificatePresentationPolicy {
    static func isAvailable(url: URL?, hasServerTrust: Bool) -> Bool {
        url?.scheme?.lowercased() == "https" && hasServerTrust
    }
}
