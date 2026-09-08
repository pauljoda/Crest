import Foundation
import WebKit

@MainActor
final class BrowserNavigationDecider {
    func decision(
        for action: WKNavigationAction,
        isAppInitiated: Bool = false
    ) -> BrowserNavigationDecision {
        switch BrowserNavigationIntent.classify(
            url: action.request.url,
            hasTargetFrame: action.targetFrame != nil,
            shouldPerformDownload: action.shouldPerformDownload,
            isAppInitiated: isAppInitiated
        ) {
        case .allow:
            return .policy(.allow)
        case .openInNewTab:
            // Allow WebKit to continue to WKUIDelegate.createWebViewWith,
            // where Crest can apply the owning Space's pop-up policy exactly once.
            return .policy(.allow)
        case .download:
            return .policy(.download)
        case .handOffToSystem(let url):
            return .handOffToSystem(url)
        case .blockScheme:
            return .policy(.cancel)
        }
    }

    nonisolated static func decidePolicy(
        canShowMIMEType: Bool,
        response: URLResponse? = nil
    ) -> WKNavigationResponsePolicy {
        switch BrowserNavigationResponseIntent.classify(
            canShowMIMEType: canShowMIMEType,
            response: response
        ) {
        case .display:
            .allow
        case .download:
            .download
        }
    }
}
