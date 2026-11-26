import Foundation
import WebKit

/// WebKit evaluates Reader Mode in its own isolated content world in the
/// web view's main frame.
@MainActor
enum BrowserReaderModeController {
    // MARK: - Static Variables

    static let contentWorld = WKContentWorld.world(name: "Crest.ReaderMode")

    // MARK: - Actions - WebKit

    static func isAvailable(in webView: WKWebView) async throws -> Bool {
        try await BrowserContentReaderModeDocument.isAvailable(evaluate: evaluator(in: webView))
    }

    static func activate(in webView: WKWebView) async throws {
        try await BrowserContentReaderModeDocument.activate(evaluate: evaluator(in: webView))
    }

    static func deactivate(in webView: WKWebView) async throws {
        try await BrowserContentReaderModeDocument.deactivate(evaluate: evaluator(in: webView))
    }

    static func snapshot(in webView: WKWebView) async throws -> BrowserReaderModeSnapshot {
        try await BrowserContentReaderModeDocument.snapshot(evaluate: evaluator(in: webView))
    }

    fileprivate static func evaluator(in webView: WKWebView) -> BrowserContentReaderModeDocument.Evaluate {
        { [weak webView] body, arguments in
            try await webView?.callAsyncJavaScript(
                body,
                arguments: arguments,
                in: nil,
                contentWorld: contentWorld
            )
        }
    }
}

extension BrowserContentReaderModeDocument {
    /// WebKit-backed Reader Mode document for macOS and iOS pages.
    convenience init(webView: WKWebView, translation: BrowserPageTranslation) {
        self.init(
            url: { [weak webView] in webView?.url },
            translation: translation,
            evaluate: BrowserReaderModeController.evaluator(in: webView)
        )
    }
}
