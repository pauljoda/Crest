import WebKit

/// Lets a page that WebKit restored from saved history hear its own Back and
/// Forward. When a page moves within its document to an entry restored from
/// saved session state, WebKit sends `popstate` but no Navigation API
/// `navigate` event, so a site that routes on `navigate`, as Reddit does, keeps
/// showing the page it left while its address and history move back.
///
/// The bridge notices a `popstate` that no traverse announced and replays the
/// move as a replace to the same address, which the site's router intercepts
/// and renders. Its own listener, added after the site's, intercepts the
/// replay too, so the replay never reloads the page, and asks for no scroll or
/// focus change, so the page keeps the position WebKit restored and the focus
/// it set. A replace drops the entry's classic `history.state`, so an entry
/// that keeps some, as popstate routers do, is left as it is: those sites
/// render on `popstate` already.
///
/// It runs in a world of its own, which the page's scripts cannot reach, and
/// only in web views that restore saved history, where WebKit drops the event.
@MainActor
enum WebKitRestoredTraversalBridge {
    // MARK: - Static Variables

    static let contentWorld = WKContentWorld.world(name: "CrestRestoredTraversal")

    static let source = #"""
        (() => {
          "use strict";
          const navigation = globalThis.navigation;
          if (!navigation) {
            return;
          }
          const addListener = EventTarget.prototype.addEventListener;
          const removeListener = EventTarget.prototype.removeEventListener;
          // The traversal WebKit announced last, until its popstate. A
          // traversal the site cancels sends none, so its announcement ends
          // with it.
          let announced = null;
          let replaying = false;
          addListener.call(navigation, "navigate", (event) => {
            if (event.navigationType !== "traverse") {
              return;
            }
            const traversal = { url: event.destination.url };
            announced = traversal;
            addListener.call(event.signal, "abort", () => {
              if (announced === traversal) {
                announced = null;
              }
            });
          });
          // Ends a replay, whether or not its navigate event came: navigate()
          // can refuse without one, as in a document that is unloading.
          let keepInDocument = null;
          const finish = () => {
            replaying = false;
            if (keepInDocument) {
              removeListener.call(navigation, "navigate", keepInDocument);
              keepInDocument = null;
            }
          };
          const cleanup = new MessageChannel();
          cleanup.port1.onmessage = finish;
          let missedEntry = null;
          const replay = () => {
            const entry = missedEntry;
            missedEntry = null;
            // A popstate listener may have moved the page on, or kept classic
            // state on the entry, since the move was missed.
            if (replaying || !entry || navigation.currentEntry?.id !== entry || history.state !== null) {
              return;
            }
            const destination = location.href;
            // Only the replay's own event: a replace to the address replayed.
            keepInDocument = (event) => {
              if (!replaying || event.navigationType !== "replace" || event.destination.url !== destination) {
                return;
              }
              finish();
              if (event.canIntercept) {
                // The replay stands in for a traversal, whose scroll WebKit
                // already restored and whose focus the page already moved; a
                // replace would scroll to the top and reset focus.
                event.intercept({ scroll: "manual", focusReset: "manual" });
              } else {
                event.preventDefault();
              }
            };
            addListener.call(navigation, "navigate", keepInDocument);
            replaying = true;
            let state;
            try {
              state = navigation.currentEntry?.getState();
            } catch (_) {}
            try {
              const result = navigation.navigate(destination, { history: "replace", state });
              result.committed.catch(() => {});
              result.finished.catch(() => {});
            } catch (_) {}
            cleanup.port2.postMessage(null);
          };
          // The replay waits for every popstate listener to run, in a task of
          // its own that timer throttling in a page out of sight never delays.
          const channel = new MessageChannel();
          channel.port1.onmessage = replay;
          addListener.call(globalThis, "popstate", () => {
            const missed = announced?.url !== location.href;
            announced = null;
            if (missed && history.state === null) {
              missedEntry = navigation.currentEntry?.id ?? null;
              channel.port2.postMessage(null);
            }
          });
        })();
        """#

    // MARK: - Actions - Installing

    /// Installs the bridge in `userContentController`, before its web view
    /// restores saved history, so the restored document runs it from its start.
    static func install(in userContentController: WKUserContentController) {
        userContentController.addUserScript(
            WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: contentWorld))
    }
}
