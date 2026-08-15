import Foundation
import WebKit

@MainActor
enum BrowserChromeWebStoreContentBridge {
    static let messageHandlerName = "crestChromeWebStore"
    static let contentWorld = WKContentWorld.world(
        name: "com.pauldavis.crest.chrome-web-store"
    )

    static func install(
        in userContentController: WKUserContentController,
        receive: @escaping @MainActor (WKScriptMessage) -> Void
    ) -> BrowserChromeWebStoreScriptMessageProxy {
        let proxy = BrowserChromeWebStoreScriptMessageProxy(receive: receive)
        userContentController.add(
            proxy,
            contentWorld: contentWorld,
            name: messageHandlerName
        )
        userContentController.addUserScript(
            WKUserScript(
                source: source,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true,
                in: contentWorld
            )
        )
        return proxy
    }

    static let source = #"""
        (() => {
          "use strict";
          if (globalThis.__crestChromeWebStoreBridge) return;
          if (location.protocol !== "https:" ||
              location.hostname !== "chromewebstore.google.com") return;

          const handler = webkit.messageHandlers.crestChromeWebStore;
          const idPattern = /^[a-p]{32}$/;
          let mountedID = null;
          let button = null;

          const item = () => {
            const parts = location.pathname.split("/").filter(Boolean);
            if (parts.length !== 3 || parts[0] !== "detail" ||
                !parts[1] || !idPattern.test(parts[2])) return null;
            return { extensionID: parts[2], url: location.href };
          };

          const targetButton = () => {
            const candidates = Array.from(
              document.querySelectorAll('button, [role="button"]')
            );
            return candidates.find((candidate) => {
              const label = (candidate.textContent || "").trim().toLowerCase();
              return label === "add to chrome" || label === "remove from chrome";
            }) || null;
          };

          const buildHost = (storeItem) => {
            const host = document.createElement("span");
            host.dataset.crestChromeWebStoreButton = storeItem.extensionID;
            host.style.display = "inline-flex";
            host.style.marginInlineStart = "8px";
            host.style.verticalAlign = "middle";
            const root = host.attachShadow({ mode: "closed" });
            button = document.createElement("a");
            button.href = "crest-extension-install://chrome-web-store/" +
              storeItem.extensionID;
            button.setAttribute("role", "button");
            button.textContent = "Add to Crest";
            button.setAttribute("aria-label", "Add this extension to Crest");
            button.style.cssText = [
              "all:initial",
              "box-sizing:border-box",
              "display:inline-flex",
              "align-items:center",
              "justify-content:center",
              "height:40px",
              "padding:0 20px",
              "border:0",
              "border-radius:20px",
              "background:#0b57d0",
              "color:white",
              "font:500 14px -apple-system,BlinkMacSystemFont,Segoe UI,sans-serif",
              "cursor:pointer",
              "white-space:nowrap"
            ].join(";");
            button.addEventListener("mouseenter", () => {
              button.style.background = "#0842a0";
            });
            button.addEventListener("mouseleave", () => {
              button.style.background = "#0b57d0";
            });
            button.addEventListener("focus", () => {
              button.style.outline = "2px solid #a8c7fa";
              button.style.outlineOffset = "2px";
            });
            button.addEventListener("blur", () => {
              button.style.outline = "none";
            });
            root.append(button);
            return host;
          };

          const mount = () => {
            const storeItem = item();
            if (!storeItem) return;
            const existing = document.querySelector(
              `[data-crest-chrome-web-store-button="${storeItem.extensionID}"]`
            );
            if (existing) {
              mountedID = storeItem.extensionID;
              return;
            }
            const target = targetButton();
            if (!target || !target.parentNode) return;
            target.insertAdjacentElement("afterend", buildHost(storeItem));
            mountedID = storeItem.extensionID;
          };

          const observer = new MutationObserver(mount);
          observer.observe(document.documentElement, { childList: true, subtree: true });
          mount();
          globalThis.__crestChromeWebStoreBridge = {
            setInstalled(extensionID) {
              if (extensionID === mountedID && button) {
                button.textContent = "Added to Crest";
                button.removeAttribute("href");
                button.setAttribute("aria-disabled", "true");
                button.style.cursor = "default";
                button.style.background = "#4d5156";
              }
            }
          };
        })();
        """#
}
