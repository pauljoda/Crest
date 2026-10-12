import CoreGraphics

/// A forwarder kept only for the sidebar's navigation metrics, which another
/// batch owns. Delete it once they read `BrowserChromeSymbolLabel.defaultPointSize`.
enum BrowserReloadFeedbackPolicy {
    static let symbolPointSize = BrowserChromeSymbolLabel.defaultPointSize
}
