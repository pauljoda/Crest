import UIKit

@MainActor
enum BrowserPageLinkClipboard {
    @discardableResult
    static func copy(_ url: URL?) -> Bool {
        guard let url else { return false }
        UIPasteboard.general.url = url
        return true
    }
}
