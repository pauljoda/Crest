import UIKit
import WebKit

/// The share sheet that offers Apple's Add to Home Screen for the page a web
/// view shows. A browser can start that flow only from a share sheet that
/// carries the page's web view, so this one leaves out the system's other
/// activities, and Add to Home Screen is the one it offers.
@MainActor
final class MobileBrowserHomeScreenActivityController: UIActivityViewController {
    // MARK: - Static Variables

    /// Every system activity except Add to Home Screen.
    private static let otherSystemActivities: [UIActivity.ActivityType] = [
        .airDrop, .message, .mail, .copyToPasteboard, .print, .addToReadingList, .assignToContact,
        .saveToCameraRoll, .markupAsPDF, .openInIBooks, .sharePlay, .collaborationInviteWithLink,
        .collaborationCopyLink, .postToFacebook, .postToTwitter, .postToWeibo, .postToTencentWeibo,
        .postToFlickr, .postToVimeo,
    ]

    // MARK: - Initializers

    init(webView: WKWebView, title: String, favicon: Data?) {
        super.init(
            activityItems: [MobileBrowserHomeScreenActivityItem(webView: webView, title: title, favicon: favicon)],
            applicationActivities: nil)
        excludedActivityTypes = Self.otherSystemActivities
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
