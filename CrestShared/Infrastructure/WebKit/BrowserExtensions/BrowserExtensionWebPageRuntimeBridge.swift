import Foundation
import WebKit
import os

/// Gives externally connectable web pages the `chrome.runtime` spelling.
///
/// WebKit installs its web-page namespace (`sendMessage` and `connect` toward
/// an installed extension) under `browser` only; its
/// `addBindingsToWebPageFrameIfNecessary` never sets `chrome`. Websites written
/// for Chrome Web Store packages call `chrome.runtime.sendMessage(extensionID,
/// message)` — claude.ai hands the OAuth code back to the Claude extension that
/// way — and find nothing on WebKit. This document-start script runs in the
/// page world and aliases `chrome.runtime` to WebKit's object on frames whose
/// URL matches one of the installed extensions' `externally_connectable.matches`
/// patterns, which is exactly where Chrome exposes it. Frames that match no
/// pattern keep `chrome` undefined, so ordinary sites never mistake Crest for
/// Chrome. The pattern set is fixed when the page is created; a page that was
/// already open when an extension was installed gains the alias on its next
/// load.
///
/// Where the alias sends is decided per frame. In a browser tab it forwards to
/// WebKit, which owns the round trip. In a frame inside a Crest-hosted
/// extension document — a side panel framing its vendor's web app, say —
/// WebKit's `runtimeWebPageSendMessage` resolves the sending page to a browser
/// tab, fails, and answers `undefined`, so the alias sends through Crest's own
/// relay instead (`BrowserExtensionWebPageRuntimeRelay`). The script decides by
/// feature detection: the relay's reply handler exists only in the web views
/// Crest builds for those documents, never in a tab.

/// Receives the page-world alias's diagnostics while extension console
/// capture is on, and writes them to the `extension-diagnostics` log beside
/// the runtime's own traces. Only message shapes travel here — a type field
/// and key names — never payload values, which for an OAuth hand-back would
/// include the authorization code.
@MainActor
final class BrowserExtensionWebPageRuntimeDiagnosticsProxy: NSObject, WKScriptMessageHandler {
    private static let log = Logger(
        subsystem: ProductIdentity.serviceNamespace, category: "extension-diagnostics"
    )

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any],
            let event = body["event"] as? String
        else { return }
        let origin = message.frameInfo.securityOrigin
        let page = "\(origin.protocol)://\(origin.host)"
        let extensionID = body["extensionId"] as? String ?? "?"
        let type = body["type"] as? String ?? "-"
        switch event {
        case "sendMessage":
            let keys = (body["keys"] as? [String])?.joined(separator: ",") ?? ""
            let form = body["form"] as? String ?? "?"
            Self.log.info(
                "web page \(page, privacy: .public) → \(extensionID, privacy: .public) runtime.sendMessage type=\(type, privacy: .public) keys=[\(keys, privacy: .public)] form=\(form, privacy: .public)"
            )
        case "sendMessageSettled":
            let outcome = body["outcome"] as? String ?? "?"
            let detail = body["detail"] as? String ?? ""
            let elapsed = body["elapsedMs"] as? Double ?? 0
            Self.log.info(
                "web page \(page, privacy: .public) → \(extensionID, privacy: .public) runtime.sendMessage type=\(type, privacy: .public) \(outcome, privacy: .public) \(detail, privacy: .public) after \(Int(elapsed), privacy: .public)ms"
            )
        case "connect":
            Self.log.info(
                "web page \(page, privacy: .public) → \(extensionID, privacy: .public) runtime.connect"
            )
        default:
            break
        }
    }
}

@MainActor
enum BrowserExtensionWebPageRuntimeBridge {
    static let contentWorld = WKContentWorld.page
    static let diagnosticsHandlerName = "crestExtensionWebPageRuntime"

    /// Installs the alias. With `reportsDiagnostics`, the script also reports
    /// every call and its outcome through the returned proxy; the caller keeps
    /// the proxy alive and removes the handler when the page goes away.
    @discardableResult
    static func install(
        in userContentController: WKUserContentController,
        matchPatterns: [String],
        reportsDiagnostics: Bool = false
    ) -> BrowserExtensionWebPageRuntimeDiagnosticsProxy? {
        guard !matchPatterns.isEmpty else { return nil }
        var proxy: BrowserExtensionWebPageRuntimeDiagnosticsProxy?
        if reportsDiagnostics {
            let diagnostics = BrowserExtensionWebPageRuntimeDiagnosticsProxy()
            userContentController.add(
                diagnostics, contentWorld: contentWorld, name: diagnosticsHandlerName
            )
            proxy = diagnostics
        }
        installScript(
            in: userContentController,
            matchPatterns: matchPatterns,
            reportsDiagnostics: reportsDiagnostics
        )
        return proxy
    }

    /// Adds the document-start script alone, for a caller that owns the
    /// diagnostics handler's lifetime itself. A user script can never be
    /// removed from a `WKUserContentController`, so a controller shared by
    /// several documents must add this exactly once.
    static func installScript(
        in userContentController: WKUserContentController,
        matchPatterns: [String],
        reportsDiagnostics: Bool = false
    ) {
        guard !matchPatterns.isEmpty else { return }
        userContentController.addUserScript(
            WKUserScript(
                source: source(matchPatterns: matchPatterns, reportsDiagnostics: reportsDiagnostics),
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false,
                in: contentWorld
            )
        )
    }

    static func source(matchPatterns: [String], reportsDiagnostics: Bool = false) -> String {
        let encoded =
            (try? JSONSerialization.data(withJSONObject: matchPatterns))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        return
            sourceTemplate
            .replacingOccurrences(of: patternsPlaceholder, with: encoded)
            .replacingOccurrences(
                of: diagnosticsPlaceholder, with: reportsDiagnostics ? "true" : "false"
            )
    }

    static let patternsPlaceholder = "__CREST_EXTERNALLY_CONNECTABLE_PATTERNS__"
    static let diagnosticsPlaceholder = "__CREST_REPORTS_DIAGNOSTICS__"

    static let sourceTemplate = #"""
        (() => {
          "use strict";
          const patterns = __CREST_EXTERNALLY_CONNECTABLE_PATTERNS__;
          if (typeof globalThis.chrome !== "undefined") return;
          const browser = globalThis.browser;
          const runtime = browser !== null && typeof browser === "object" ? browser.runtime : undefined;
          const hasNativeRuntime = !!runtime
            && typeof runtime.sendMessage === "function"
            && typeof runtime.connect === "function";
          // Crest's own route into an extension, present only in the web views
          // Crest builds for a hosted extension document (a side panel or an
          // offscreen document). A browser tab never installs it, so a tab's
          // alias behaves exactly as it did before.
          const relay = (() => {
            try {
              const handler = globalThis.webkit?.messageHandlers?.crestExtensionWebPageRuntimeRelay;
              return typeof handler?.postMessage === "function" ? handler : undefined;
            } catch (_) { return undefined; }
          })();
          if (!hasNativeRuntime && relay === undefined) return;
          // Read the frame's own location parts rather than parsing `href`
          // through `URL`: the page world always has both, and a bare
          // JavaScriptCore context (the unit tests) has only `location`.
          const location = globalThis.location;
          if (!location || typeof location.hostname !== "string") return;
          const escapeForRegExp = (text) => text.replace(/[.+?^${}()|[\]\\]/g, "\\$&");
          const globToRegExp = (text) => new RegExp("^" + text.split("*").map(escapeForRegExp).join(".*") + "$");
          const protocol = String(location.protocol || "").replace(/:$/, "").toLowerCase();
          const hostname = location.hostname.toLowerCase();
          const pathAndQuery = String(location.pathname || "/") + String(location.search || "");
          const matches = (pattern) => {
            if (typeof pattern !== "string") return false;
            if (pattern === "<all_urls>") return ["http", "https", "ws", "wss", "ftp", "file"].includes(protocol);
            const parsed = /^(\*|https?|wss?|ftp|file):\/\/(\*|\*\.[^/*]+|[^/*]*)(\/.*)$/.exec(pattern);
            if (!parsed) return false;
            const [, scheme, host, path] = parsed;
            if (scheme === "*" ? !(protocol === "http" || protocol === "https") : scheme !== protocol) return false;
            if (host !== "*") {
              const wanted = host.toLowerCase();
              if (wanted.startsWith("*.")) {
                const suffix = wanted.slice(2);
                if (hostname !== suffix && !hostname.endsWith("." + suffix)) return false;
              } else if (hostname !== wanted) {
                return false;
              }
            }
            return globToRegExp(path).test(pathAndQuery);
          };
          if (!patterns.some(matches)) return;
          const reportsDiagnostics = __CREST_REPORTS_DIAGNOSTICS__;
          const report = (body) => {
            if (!reportsDiagnostics) return;
            try { globalThis.webkit?.messageHandlers?.crestExtensionWebPageRuntime?.postMessage(body); } catch (_) {}
          };
          // Shapes only: a type field and key names, never values.
          const shape = (value) => {
            if (value === undefined) return { valueType: "undefined" };
            if (value === null || typeof value !== "object") return { valueType: typeof value };
            return {
              type: typeof value.type === "string" ? value.type : undefined,
              keys: Object.keys(value).slice(0, 12),
            };
          };
          const describe = (reply) => {
            const s = shape(reply);
            return s.keys ? `keys=[${s.keys.join(",")}]` : s.valueType;
          };
          // Chrome reports "nobody answered" through `chrome.runtime.lastError`
          // (set only while the callback runs) or a rejected promise. WebKit
          // answers an unknown extension, an unmatched page, or a silent
          // listener with a plain `undefined` reply. Pages rely on the Chrome
          // signal: claude.ai probes several extension ids in turn and treats
          // an error-free `undefined` as a completed hand-off, so without it
          // the sign-in never reaches the installed extension.
          const receivingEndError = "Could not establish connection. Receiving end does not exist.";
          let lastError;
          // WebKit's own web-page `sendMessage` resolves the sending page to a
          // browser tab and drops the message when it cannot. A frame inside a
          // Crest-hosted extension document never resolves to one — Chrome's
          // side panel is not a tab either, which is why `sender.tab` is
          // undefined there — so WebKit answers `undefined` after a delay.
          // Prefer Crest's relay in exactly that situation, and keep WebKit
          // first everywhere else so an ordinary tab's round trip stays inside
          // the engine that owns it.
          const framedByExtensionDocument = (() => {
            try {
              const ancestors = globalThis.location?.ancestorOrigins;
              if (!ancestors || ancestors.length === 0) return false;
              for (let index = 0; index < ancestors.length; index += 1) {
                if (String(ancestors[index] ?? "").startsWith("chrome-extension://")) return true;
              }
              return false;
            } catch (_) { return false; }
          })();
          const prefersRelay = relay !== undefined && (framedByExtensionDocument || !hasNativeRuntime);
          // The relay's reply handler answers with a Promise. `null` is its
          // refusal and its "nobody answered", which is the same thing to the
          // page: Crest never tells a website which extensions exist.
          const relayReply = (extensionId, message) => {
            let returned;
            try {
              returned = relay.postMessage({ extensionId: String(extensionId), message });
            } catch (error) {
              return Promise.reject(error);
            }
            return Promise.resolve(returned).then((reply) => (reply === null ? undefined : reply));
          };
          // Chrome resolves `sendMessage(extensionId, message, callback)` by
          // recognizing the function; place it in WebKit's callback slot
          // explicitly rather than relying on positional matching.
          const sendMessage = (extensionId, message, ...rest) => {
            const callback = typeof rest[rest.length - 1] === "function" ? rest.pop() : undefined;
            const options = rest.length > 0 && rest[0] !== null && typeof rest[0] === "object" ? rest[0] : undefined;
            const summary = shape(message);
            const started = Date.now();
            report({ event: "sendMessage", extensionId: String(extensionId), type: summary.type, keys: summary.keys ?? [], form: callback ? "callback" : "promise" });
            const settle = (outcome, detail) => report({
              event: "sendMessageSettled", extensionId: String(extensionId), type: summary.type, outcome, detail, elapsedMs: Date.now() - started,
            });
            // A relayed answer always arrives as a Promise. Deliver it in
            // whichever form the page asked for, with the same `lastError`
            // and rejection semantics WebKit's answer gets.
            const deliverRelayed = (answer) => {
              if (callback !== undefined) {
                answer.then(
                  (reply) => {
                    const unanswered = reply === undefined;
                    settle(unanswered ? "unanswered" : "replied", describe(reply));
                    lastError = unanswered ? { message: receivingEndError } : undefined;
                    try { callback(reply); } finally { lastError = undefined; }
                  },
                  (error) => {
                    settle("rejected", String(error && error.message ? error.message : error));
                    lastError = { message: receivingEndError };
                    try { callback(undefined); } finally { lastError = undefined; }
                  },
                );
                return undefined;
              }
              return answer.then(
                (reply) => {
                  settle(reply === undefined ? "unanswered" : "replied", describe(reply));
                  if (reply === undefined) throw new Error(receivingEndError);
                  return reply;
                },
                (error) => {
                  settle("rejected", String(error && error.message ? error.message : error));
                  throw error;
                },
              );
            };
            if (prefersRelay) {
              return deliverRelayed(relayReply(extensionId, message));
            }
            try {
              if (callback !== undefined) {
                return runtime.sendMessage(extensionId, message, options, (reply) => {
                  // WebKit could not route it. If Crest can, ask Crest before
                  // telling the page nobody answered.
                  if (reply === undefined && relay !== undefined) {
                    deliverRelayed(relayReply(extensionId, message));
                    return undefined;
                  }
                  const unanswered = reply === undefined;
                  settle(unanswered ? "unanswered" : "replied", describe(reply));
                  lastError = unanswered ? { message: receivingEndError } : undefined;
                  try {
                    return callback(reply);
                  } finally {
                    lastError = undefined;
                  }
                });
              }
              const result = options === undefined
                ? runtime.sendMessage(extensionId, message)
                : runtime.sendMessage(extensionId, message, options);
              if (result && typeof result.then === "function") {
                return result.then(
                  (reply) => {
                    if (reply === undefined && relay !== undefined) {
                      return deliverRelayed(relayReply(extensionId, message));
                    }
                    settle(reply === undefined ? "unanswered" : "replied", describe(reply));
                    if (reply === undefined) throw new Error(receivingEndError);
                    return reply;
                  },
                  (error) => {
                    settle("rejected", String(error && error.message ? error.message : error));
                    throw error;
                  },
                );
              }
              return result;
            } catch (error) {
              settle("threw", String(error && error.message ? error.message : error));
              throw error;
            }
          };
          const chromeRuntime = {
            sendMessage,
            // Crest relays one-shot messages only. A long-lived port stays
            // WebKit's, and a document with no web-page namespace at all
            // reports the connection failure Chrome reports.
            connect: (extensionId, connectInfo) => {
              report({ event: "connect", extensionId: String(extensionId) });
              if (!hasNativeRuntime) throw new Error(receivingEndError);
              return runtime.connect(extensionId, connectInfo);
            },
          };
          Object.defineProperty(chromeRuntime, "lastError", {
            get: () => lastError,
            enumerable: true,
            configurable: true,
          });
          globalThis.chrome = { runtime: chromeRuntime };
        })();
        """#
}
