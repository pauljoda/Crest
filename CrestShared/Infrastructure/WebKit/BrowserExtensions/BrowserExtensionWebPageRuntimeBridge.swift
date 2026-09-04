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
        userContentController.addUserScript(
            WKUserScript(
                source: source(matchPatterns: matchPatterns, reportsDiagnostics: reportsDiagnostics),
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false,
                in: contentWorld
            )
        )
        return proxy
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
          if (!runtime || typeof runtime.sendMessage !== "function" || typeof runtime.connect !== "function") return;
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
            try {
              if (callback !== undefined) {
                return runtime.sendMessage(extensionId, message, options, (reply) => {
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
            connect: (extensionId, connectInfo) => {
              report({ event: "connect", extensionId: String(extensionId) });
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
