import WebKit

/// Measures the live document without changing its viewport or scroll position.
/// The isolated content world keeps page-defined globals and getters out of the
/// measurement. Legacy CDP dimensions use physical pixels; CSS metrics do not.
@MainActor
enum BrowserChromeDebuggerLayoutMetrics {
    static func measure(_ webView: WKWebView) async throws -> [String: Any] {
        let result = try await webView.callAsyncJavaScript(
            """
            const root = document.compatMode === 'BackCompat' ? document.body : document.documentElement;
            const scroller = document.scrollingElement || root;
            const viewport = window.visualViewport;
            if (!root || !viewport) throw new Error('The document has no layout viewport');
            const layout = {
                pageX: Math.round(window.scrollX), pageY: Math.round(window.scrollY),
                clientWidth: root.clientWidth, clientHeight: root.clientHeight
            };
            const visual = {
                offsetX: viewport.offsetLeft, offsetY: viewport.offsetTop,
                pageX: viewport.pageLeft, pageY: viewport.pageTop,
                clientWidth: viewport.width, clientHeight: viewport.height,
                scale: viewport.scale, zoom: pageZoom
            };
            const content = {
                x: 0, y: 0,
                width: Math.max(root.clientWidth, scroller.scrollWidth),
                height: Math.max(root.clientHeight, scroller.scrollHeight)
            };
            const ratio = window.devicePixelRatio;
            return {
                cssLayoutViewport: layout, cssVisualViewport: visual, cssContentSize: content,
                layoutViewport: {
                    pageX: Math.round(window.scrollX * ratio), pageY: Math.round(window.scrollY * ratio),
                    clientWidth: Math.round(layout.clientWidth * ratio),
                    clientHeight: Math.round(layout.clientHeight * ratio)
                },
                // Chromium's legacy visual offsets remain CSS pixels; only its dimensions scale.
                visualViewport: { ...visual,
                    clientWidth: visual.clientWidth * ratio, clientHeight: visual.clientHeight * ratio
                },
                contentSize: { x: 0, y: 0, width: content.width * ratio, height: content.height * ratio }
            };
            """,
            arguments: ["pageZoom": webView.pageZoom], in: nil, contentWorld: .defaultClient)
        guard let metrics = result as? [String: Any] else {
            throw BrowserChromeDebuggerProtocolError.invalidResult
        }
        return metrics
    }
}
