import Foundation
import WebKit

extension BrowserDownloadCenter {
    /// The center's WebKit transport, created with the first WebKit download.
    var webKitTransport: BrowserWebKitDownloadTransport {
        transport { BrowserWebKitDownloadTransport(center: $0) }
    }

    /// Records and runs a download a WebKit page handed Crest.
    func start(
        _ download: WKDownload,
        in webView: WKWebView,
        profileID: UUID,
        spaceID: SpaceID,
        spaceName: String,
        isUserInitiated: Bool? = nil,
        feedbackSource: BrowserDownloadFeedbackSource? = nil,
        suggestedFilenameOverride: String? = nil,
        forcesDestinationPrompt: Bool = false
    ) {
        webKitTransport.start(
            download, in: webView, profileID: profileID, spaceID: spaceID, spaceName: spaceName,
            isUserInitiated: isUserInitiated, feedbackSource: feedbackSource,
            suggestedFilenameOverride: suggestedFilenameOverride,
            forcesDestinationPrompt: forcesDestinationPrompt)
    }
}
