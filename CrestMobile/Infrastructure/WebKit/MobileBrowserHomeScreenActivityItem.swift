import LinkPresentation
import UIKit
import WebKit

/// The page a web view shows, as the share sheet's one item: the web view,
/// which WebKit needs to offer Add to Home Screen, with the page's title,
/// address and icon for the sheet's header.
final class MobileBrowserHomeScreenActivityItem: NSObject, UIActivityItemSource {
    // MARK: - Variables

    private let webView: WKWebView
    private let metadata: LPLinkMetadata

    // MARK: - Initializers

    @MainActor
    init(webView: WKWebView, title: String, favicon: Data?) {
        self.webView = webView
        metadata = LPLinkMetadata()
        metadata.originalURL = webView.url
        metadata.url = webView.url
        metadata.title = title.isEmpty ? webView.url?.host() : title
        metadata.iconProvider = favicon.flatMap(UIImage.init(data:)).map(NSItemProvider.init(object:))
        super.init()
    }

    // MARK: - Actions - Sharing

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        webView
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        webView
    }

    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        metadata
    }
}
