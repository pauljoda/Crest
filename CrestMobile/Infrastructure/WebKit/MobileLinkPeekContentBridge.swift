import Dispatch
import Observation
import UIKit
import UniformTypeIdentifiers
import WebKit

@MainActor
enum MobileLinkPeekContentBridge {
    static let messageHandlerName = "crestLinkPeekPress"
    static let contentWorld = WKContentWorld.world(
        name: "com.pauldavis.crest.link-peek-press"
    )

    static func install(
        in userContentController: WKUserContentController
    ) -> MobileLinkPeekScriptMessageProxy {
        let proxy = MobileLinkPeekScriptMessageProxy()
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
          if (globalThis.__crestLinkPeekPressInstalled) return;
          globalThis.__crestLinkPeekPressInstalled = true;

          let activePress = null;
          let pressSequence = 0;
          let suppressClickUntil = -Infinity;

          const post = payload => {
            try {
              globalThis.webkit.messageHandlers.crestLinkPeekPress.postMessage(payload);
            } catch (_) {}
          };

          const finish = phase => {
            if (!activePress) return;
            const pressID = activePress.pressID;
            clearTimeout(activePress.holdTimer);
            for (const [property, value, priority] of activePress.previousSelectionStyles) {
              if (value) {
                activePress.link.style.setProperty(property, value, priority);
              } else {
                activePress.link.style.removeProperty(property);
              }
            }
            activePress = null;
            post({ phase, pressID });
          };

          globalThis.addEventListener('pointerdown', event => {
            if (!event.isTrusted || (event.button !== undefined && event.button !== 0)) return;
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
            const selectionProperties = [
              '-webkit-user-select',
              'user-select',
              '-webkit-touch-callout',
              '-webkit-tap-highlight-color'
            ];
            const previousSelectionStyles = selectionProperties.map(property => [
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
              previousSelectionStyles,
              holdTimer: setTimeout(() => {
                if (activePress?.pressID === pressID) {
                  suppressClickUntil = performance.now() + 900;
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
