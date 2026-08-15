import Foundation
import WebKit

@MainActor
final class BrowserDownloadRetryContext {
    weak var webView: WKWebView?
    let request: URLRequest
    let assignment: BrowserSpaceRuntimeAssignment
    let spaceName: String

    init(
        webView: WKWebView,
        request: URLRequest,
        profileID: UUID,
        spaceID: SpaceID,
        spaceName: String
    ) {
        self.webView = webView
        self.request = request
        assignment = BrowserSpaceRuntimeAssignment(
            spaceID: spaceID,
            profileID: profileID
        )
        self.spaceName = spaceName
    }
}
