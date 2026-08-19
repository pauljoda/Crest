import Foundation
import WebKit

/// Reports the link and image under the cursor to the app before WebKit builds its
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

          const post = (href, imageURL) => {
            try {
              webkit.messageHandlers.crestLinkContext.postMessage({
                version: 2,
                token: ++sequence,
                href,
                imageURL
              });
            } catch (_) {}
          };

          const elementFromEvent = (event, selector) => {
            const path = typeof event.composedPath === "function"
              ? event.composedPath()
              : [];
            const composedElement = path.find((node) =>
              node instanceof Element && node.matches?.(selector)
            );
            if (composedElement) return composedElement;
            return event.target instanceof Element
              ? event.target.closest(selector)
              : null;
          };

          const linkFromEvent = (event) => {
            return elementFromEvent(event, "a[href], area[href]");
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

          const imageDestination = (event) => {
            const image = elementFromEvent(
              event,
              "img, input[type='image'], svg image"
            );
            if (!image) return null;
            const raw = image.currentSrc
              || (typeof image.src === "string" ? image.src : null)
              || image.href?.baseVal
              || image.getAttribute("href")
              || image.getAttribute("src");
            if (!raw) return null;
            let resolved;
            try {
              resolved = new URL(raw, image.baseURI || document.baseURI);
            } catch (_) {
              return null;
            }
            if (!["http:", "https:", "blob:", "data:"].includes(resolved.protocol)) {
              return null;
            }
            return resolved.href.length <= 4096 ? resolved.href : null;
          };

          globalThis.addEventListener("contextmenu", (event) => {
            if (!event.isTrusted) return;
            post(destination(event), imageDestination(event));
          }, { capture: true, passive: true });
        })();
        """#
}
