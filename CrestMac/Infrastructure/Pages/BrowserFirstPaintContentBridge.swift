import Foundation

/// Tells a page when its document first paints content of its own, as the
/// Paint Timing API reports it. The canonical JavaScript source lives in
/// `CrestCore` so every platform and engine runs the same bridge.
@MainActor
enum BrowserFirstPaintContentBridge {
    // MARK: - Static Variables

    static let messageHandlerName = ContentBridge.firstPaint.handlerName

    static let source: String = ContentBridge.firstPaint.script().source

    /// The bridge as an engine that runs Crest's content bridges itself takes it.
    static var script: BrowserContentScript {
        ContentBridge.firstPaint.contentScript()
    }
}
