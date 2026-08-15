import Foundation
import WebKit

/// Mounts Crest's "Add to Crest" control on an addons.mozilla.org detail page.
///
/// The script runs in an isolated content world behind a closed shadow root, so
/// the page can neither read nor restyle the control, and it carries no
/// privilege of its own: activating it only navigates to a private scheme that
/// `BrowserMozillaAddonsInstallNavigation` re-validates against the page the
/// web view is actually showing.
///
/// AMO renders a different install component for a non-Firefox user agent —
/// `GetFirefoxButton` instead of `AMInstallButton` — so the mount point is
/// `.Addon-install > .InstallButtonWrapper`, the one node present in both
/// branches and in every locale. Matching on the button's own class or its
/// English label would never find anything under Crest's WebKit user agent.
@MainActor
enum BrowserMozillaAddonsContentBridge {
    static let contentWorld = WKContentWorld.world(
        name: "com.pauldavis.crest.mozilla-addons"
    )

    static func install(in userContentController: WKUserContentController) {
        userContentController.addUserScript(
            WKUserScript(
                source: source,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true,
                in: contentWorld
            )
        )
    }

    static let source = #"""
        (() => {
          "use strict";
          if (globalThis.__crestMozillaAddonsBridge) return;
          if (location.protocol !== "https:" ||
              location.hostname !== "addons.mozilla.org") return;

          const pathPattern =
            /^\/[A-Za-z]{1,3}(?:-[A-Za-z0-9]{1,8})?\/(?:firefox|android)\/addon\/([A-Za-z0-9_-]{1,100})\/$/;
          const hostAttribute = "data-crest-mozilla-addons-button";
          let mountedSlug = null;
          let button = null;

          const addon = () => {
            const match = pathPattern.exec(location.pathname);
            if (!match) return null;
            // Themes and language packs use the identical install markup and
            // are not WebExtensions Crest can host.
            const root = document.querySelector(".Addon");
            if (!root || !root.classList.contains("Addon-extension")) {
              return null;
            }
            return { slug: match[1] };
          };

          const buildHost = (entry) => {
            const host = document.createElement("div");
            host.setAttribute(hostAttribute, entry.slug);
            host.style.display = "block";
            host.style.marginBlockStart = "8px";
            const root = host.attachShadow({ mode: "closed" });
            button = document.createElement("a");
            button.href =
              "crest-extension-install://mozilla-addons/" + entry.slug;
            button.setAttribute("role", "button");
            button.textContent = "Add to Crest";
            button.setAttribute("aria-label", "Add this extension to Crest");
            button.style.cssText = [
              "all:initial",
              "box-sizing:border-box",
              "display:flex",
              "align-items:center",
              "justify-content:center",
              "width:100%",
              "height:48px",
              "padding:0 20px",
              "border:0",
              "border-radius:4px",
              "background:#0060df",
              "color:white",
              "font:600 15px -apple-system,BlinkMacSystemFont,Segoe UI,sans-serif",
              "cursor:pointer",
              "white-space:nowrap"
            ].join(";");
            button.addEventListener("mouseenter", () => {
              button.style.background = "#0250bb";
            });
            button.addEventListener("mouseleave", () => {
              button.style.background = "#0060df";
            });
            button.addEventListener("focus", () => {
              button.style.outline = "2px solid #0a84ff";
              button.style.outlineOffset = "2px";
            });
            button.addEventListener("blur", () => {
              button.style.outline = "none";
            });
            root.append(button);
            return host;
          };

          const mount = () => {
            const entry = addon();
            const existing = document.querySelector("[" + hostAttribute + "]");
            if (!entry) {
              if (existing) existing.remove();
              mountedSlug = null;
              button = null;
              return;
            }
            if (existing) {
              if (existing.getAttribute(hostAttribute) === entry.slug) {
                mountedSlug = entry.slug;
                return;
              }
              // Single-page navigation reached a different add-on.
              existing.remove();
              button = null;
            }
            const wrapper = document.querySelector(
              ".Addon-install > .InstallButtonWrapper"
            );
            if (!wrapper) return;
            wrapper.insertAdjacentElement("afterend", buildHost(entry));
            mountedSlug = entry.slug;
          };

          const observer = new MutationObserver(mount);
          observer.observe(document.documentElement, {
            childList: true,
            subtree: true
          });
          mount();
          globalThis.__crestMozillaAddonsBridge = {
            setInstalled(slug) {
              if (slug === mountedSlug && button) {
                button.textContent = "Added to Crest";
                button.removeAttribute("href");
                button.setAttribute("aria-disabled", "true");
                button.style.cursor = "default";
                button.style.background = "#5b5b66";
              }
            }
          };
        })();
        """#
}
