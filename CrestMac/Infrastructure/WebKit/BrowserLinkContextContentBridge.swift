import Foundation
import WebKit

/// Reports the link under the cursor to the app before WebKit builds its
/// web-content context menu.
///
/// macOS has no `contextMenuConfigurationForElement` — that delegate callback
/// is iOS only — and resolving the element from `rightMouseDown` races WebKit's
/// own hit test. The `contextmenu` DOM event does not race it: the web content
/// process dispatches the event first and only then answers the UI process with
/// the menu, and messages from one process arrive in the order it sent them.
///
/// The listener runs in the capture phase, before page script can cancel
/// propagation, and posts on *every* right-click — including one that found no
/// link, which is what keeps the previous capture from surviving into a menu
/// opened over plain content.
@MainActor
enum BrowserLinkContextContentBridge {
    static let messageHandlerName = "crestLinkContext"
    static let contentWorld = WKContentWorld.world(
        name: "com.pauldavis.crest.link-context"
    )

    static func install(
        in userContentController: WKUserContentController,
        receive: @escaping @MainActor (WKScriptMessage) -> Void
    ) -> BrowserLinkContextScriptMessageProxy {
        let proxy = BrowserLinkContextScriptMessageProxy(receive: receive)
        userContentController.add(
            proxy,
            contentWorld: contentWorld,
            name: messageHandlerName
        )
        userContentController.addUserScript(
            WKUserScript(
                source: source,
                injectionTime: .atDocumentStart,
                // A link inside an iframe opens the same menu as one in the
                // main frame, so every frame reports for itself.
                forMainFrameOnly: false,
                in: contentWorld
            )
        )
        return proxy
    }

    static let source = #"""
        (() => {
          "use strict";
          if (globalThis.__crestLinkContextBridgeInstalled) return;
          globalThis.__crestLinkContextBridgeInstalled = true;

          let sequence = 0;

          const post = (href) => {
            try {
              webkit.messageHandlers.crestLinkContext.postMessage({
                version: 1,
                token: ++sequence,
                href
              });
            } catch (_) {}
          };

          const linkFromEvent = (event) => {
            const path = typeof event.composedPath === "function"
              ? event.composedPath()
              : [];
            const composedLink = path.find((node) =>
              node instanceof Element && node.matches?.("a[href], area[href]")
            );
            if (composedLink) return composedLink;
            return event.target instanceof Element
              ? event.target.closest("a[href], area[href]")
              : null;
          };

          const destination = (event) => {
            const link = linkFromEvent(event);
            if (!link) return null;
            // An SVG anchor answers `href` with an SVGAnimatedString rather
            // than a resolved URL string, so fall back to the attribute and
            // let the element's own base document resolve it.
            const raw = typeof link.href === "string"
              ? link.href
              : link.getAttribute("href");
            if (!raw) return null;
            let resolved;
            try {
              resolved = new URL(raw, link.baseURI || document.baseURI);
            } catch (_) {
              return null;
            }
            if (resolved.protocol !== "http:" && resolved.protocol !== "https:") {
              return null;
            }
            return resolved.href;
          };

          globalThis.addEventListener("contextmenu", (event) => {
            if (!event.isTrusted) return;
            post(destination(event));
          }, { capture: true, passive: true });
        })();
        """#
}
