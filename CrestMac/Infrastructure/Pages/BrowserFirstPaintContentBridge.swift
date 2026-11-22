import Foundation

/// Tells a page when its document first paints content of its own, as the
/// Paint Timing API reports it. Until then the engine shows only the page's
/// bare background, which is white before the page's styles apply, so a page
/// opening in dark mode would flash white between its loading screen and its
/// content. It runs in the main frame of every document, in Crest's own world,
/// on both engines.
@MainActor
enum BrowserFirstPaintContentBridge {
    static let messageHandlerName = "crestFirstPaint"

    /// The bridge as an engine that runs Crest's content bridges itself takes it.
    static var script: BrowserContentScript {
        BrowserContentScript(source: source, handlerName: messageHandlerName, mainFrameOnly: true)
    }

    static let source = #"""
        (() => {
          "use strict";
          const handler = globalThis.webkit?.messageHandlers?.crestFirstPaint;
          if (!handler || typeof PerformanceObserver !== "function") return;
          try {
            const observer = new PerformanceObserver(list => {
              if (!list.getEntries().some(entry => entry.name === "first-contentful-paint")) return;
              observer.disconnect();
              try { handler.postMessage(true); } catch (_) {}
            });
            observer.observe({ type: "paint", buffered: true });
          } catch (_) {}
        })();
        """#
}
