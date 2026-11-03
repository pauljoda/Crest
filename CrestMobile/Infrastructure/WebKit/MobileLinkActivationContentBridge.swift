import Dispatch
import Observation
import UIKit
import UniformTypeIdentifiers
import WebKit

/// Reports a press on a link with its geometry, and when it began, ended or
/// was cancelled, so a held press opens Peek from the link. While a link is
/// held, it neither selects text nor shows the system's link callout, and the
/// click that ends a held press doesn't follow the link. Images and every other
/// element keep WebKit's own menus.
@MainActor
enum MobileLinkActivationContentBridge {
    static let messageHandlerName = "crestLinkActivation"
    static let contentWorld = WKContentWorld.world(
        name: "com.pauldavis.crest.link-activation"
    )

    static func install(
        in userContentController: WKUserContentController
    ) -> MobileLinkActivationScriptMessageProxy {
        let proxy = MobileLinkActivationScriptMessageProxy()
        userContentController.add(
            proxy,
            contentWorld: contentWorld,
            name: messageHandlerName
        )
        userContentController.addUserScript(
            WKUserScript(
                source: source,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false,
                in: contentWorld
            )
        )
        return proxy
    }

    private static let source = #"""
        (() => {
          if (globalThis.__crestLinkActivationInstalled) return;
          globalThis.__crestLinkActivationInstalled = true;

          let activePress = null;
          let pressSequence = 0;
          // The click that ends a held press is swallowed: the press arms it
          // once held, and its release opens a short window for that click.
          let endingClickArmed = false;
          let suppressClickUntil = -Infinity;

          const post = payload => {
            try {
              globalThis.webkit.messageHandlers.crestLinkActivation.postMessage(payload);
            } catch (_) {}
          };

          const finish = phase => {
            if (!activePress) return;
            const pressID = activePress.pressID;
            clearTimeout(activePress.holdTimer);
            for (const [property, value, priority] of activePress.previousStyles) {
              if (value) {
                activePress.link.style.setProperty(property, value, priority);
              } else {
                activePress.link.style.removeProperty(property);
              }
            }
            activePress = null;
            // A cancelled press opened no Peek, so a click it ends with follows
            // the link like any other.
            suppressClickUntil = phase === 'ended' && endingClickArmed ? performance.now() + 500 : -Infinity;
            endingClickArmed = false;
            post({ phase, pressID });
          };

          globalThis.addEventListener('pointerdown', event => {
            if (!event.isTrusted || (event.button !== undefined && event.button !== 0)) return;
            suppressClickUntil = -Infinity;
            const target = event.target instanceof Element ? event.target : null;
            const link = event.composedPath().find(
              node => node instanceof Element && node.matches?.('a[href], area[href]')
            ) || target?.closest?.('a[href], area[href]');
            if (!link) return;

            let destination;
            try {
              destination = new URL(link.href, document.baseURI);
            } catch (_) {
              return;
            }
            if (destination.protocol !== 'http:' && destination.protocol !== 'https:') return;

            if (activePress) finish('cancelled');
            const rect = link.getBoundingClientRect();
            const viewportWidth = Math.max(globalThis.innerWidth, 1);
            const viewportHeight = Math.max(globalThis.innerHeight, 1);
            const pressID = `${Date.now()}-${++pressSequence}`;
            const label = (
              link.innerText ||
              link.getAttribute('aria-label') ||
              link.getAttribute('title') ||
              destination.hostname
            ).trim();
            // The held link keeps its text and its callout to itself, so the
            // press opens Peek rather than a selection or the link menu.
            const heldProperties = [
              '-webkit-user-select',
              'user-select',
              '-webkit-touch-callout',
              '-webkit-tap-highlight-color'
            ];
            const previousStyles = heldProperties.map(property => [
              property,
              link.style.getPropertyValue(property),
              link.style.getPropertyPriority(property)
            ]);
            link.style.setProperty('-webkit-user-select', 'none', 'important');
            link.style.setProperty('user-select', 'none', 'important');
            link.style.setProperty('-webkit-touch-callout', 'none', 'important');
            link.style.setProperty('-webkit-tap-highlight-color', 'transparent', 'important');

            activePress = {
              pressID,
              pointerID: event.pointerId,
              startX: event.clientX,
              startY: event.clientY,
              link,
              previousStyles,
              holdTimer: setTimeout(() => {
                if (activePress?.pressID === pressID) {
                  endingClickArmed = true;
                  globalThis.getSelection()?.removeAllRanges();
                }
              }, 280)
            };

            post({
              phase: 'began',
              pressID,
              href: destination.href,
              label,
              minX: rect.left / viewportWidth,
              minY: rect.top / viewportHeight,
              width: rect.width / viewportWidth,
              height: rect.height / viewportHeight,
              touchX: event.clientX / viewportWidth,
              touchY: event.clientY / viewportHeight
            });
          }, { capture: true, passive: true });

          globalThis.addEventListener('pointermove', event => {
            if (!activePress || event.pointerId !== activePress.pointerID) return;
            const distance = Math.hypot(
              event.clientX - activePress.startX,
              event.clientY - activePress.startY
            );
            if (distance > 16) finish('cancelled');
          }, { capture: true, passive: true });

          globalThis.addEventListener('pointerup', event => {
            if (activePress?.pointerID === event.pointerId) finish('ended');
          }, { capture: true, passive: true });

          globalThis.addEventListener('pointercancel', event => {
            if (activePress?.pointerID === event.pointerId) finish('cancelled');
            suppressClickUntil = -Infinity;
          }, { capture: true, passive: true });

          globalThis.addEventListener('selectstart', event => {
            if (activePress) event.preventDefault();
          }, { capture: true });

          globalThis.addEventListener('contextmenu', event => {
            if (activePress) event.preventDefault();
          }, { capture: true });

          globalThis.addEventListener('click', event => {
            if (performance.now() >= suppressClickUntil) return;
            suppressClickUntil = -Infinity;
            event.preventDefault();
            event.stopImmediatePropagation();
          }, { capture: true });
        })();
        """#
}
