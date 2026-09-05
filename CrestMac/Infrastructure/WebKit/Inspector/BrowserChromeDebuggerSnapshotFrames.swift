import Foundation
import WebKit

@MainActor
enum BrowserChromeDebuggerSnapshotFrames {
    /// The engine supplies WKFrameInfo, which callAsyncJavaScript can target
    /// without navigating or relying on a page's cross-origin window objects.
    static func read(in webView: WKWebView) async throws -> [WKFrameInfo] {
        let selector = NSSelectorFromString("_frames:")
        guard webView.responds(to: selector) else {
            throw BrowserChromeDebuggerProtocolError.unsupportedCommand("DOMSnapshot.captureSnapshot")
        }
        let result: FrameResult = await withCheckedContinuation { continuation in
            let callback: @convention(block) (NSObject?) -> Void = { node in
                MainActor.assumeIsolated { continuation.resume(returning: FrameResult(node: node)) }
            }
            webView.perform(selector, with: callback)
        }
        var frames: [WKFrameInfo] = []
        try Task.checkCancellation()
        guard let root = result.node else { throw BrowserChromeDebuggerProtocolError.invalidResult }
        var queue = [root]
        var cursor = 0
        while cursor < queue.count {
            let node = queue[cursor]
            cursor += 1
            let infoSelector = NSSelectorFromString("info")
            let childrenSelector = NSSelectorFromString("childFrames")
            guard node.responds(to: infoSelector), node.responds(to: childrenSelector),
                let info = node.perform(infoSelector)?.takeUnretainedValue() as? WKFrameInfo,
                info.webView === webView,
                let children = node.perform(childrenSelector)?.takeUnretainedValue() as? [NSObject]
            else { throw BrowserChromeDebuggerProtocolError.invalidResult }
            frames.append(info)
            queue += children
        }
        guard frames.first?.isMainFrame == true else { throw BrowserChromeDebuggerProtocolError.invalidResult }
        return frames
    }

    /// Only main-actor code can access the non-Sendable Objective-C tree.
    @MainActor
    private final class FrameResult {
        let node: NSObject?
        init(node: NSObject?) { self.node = node }
    }
}
