import Foundation
import WebKit

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
@MainActor
enum BrowserExtensionWebPageRuntimeBridge {
    static let contentWorld = WKContentWorld.page

    static func install(
        in userContentController: WKUserContentController,
        matchPatterns: [String]
    ) {
        guard !matchPatterns.isEmpty else { return }
        userContentController.addUserScript(
            WKUserScript(
                source: source(matchPatterns: matchPatterns),
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false,
                in: contentWorld
            )
        )
    }

    static func source(matchPatterns: [String]) -> String {
        let encoded =
            (try? JSONSerialization.data(withJSONObject: matchPatterns))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        return sourceTemplate.replacingOccurrences(
            of: patternsPlaceholder, with: encoded
        )
    }

    static let patternsPlaceholder = "__CREST_EXTERNALLY_CONNECTABLE_PATTERNS__"

    static let sourceTemplate = #"""
        (() => {
          "use strict";
          const patterns = __CREST_EXTERNALLY_CONNECTABLE_PATTERNS__;
          if (typeof globalThis.chrome !== "undefined") return;
          const browser = globalThis.browser;
          const runtime = browser !== null && typeof browser === "object" ? browser.runtime : undefined;
          if (!runtime || typeof runtime.sendMessage !== "function" || typeof runtime.connect !== "function") return;
          let url;
          try { url = new URL(globalThis.location.href); } catch (_) { return; }
          const escapeForRegExp = (text) => text.replace(/[.+?^${}()|[\]\\]/g, "\\$&");
          const globToRegExp = (text) => new RegExp("^" + text.split("*").map(escapeForRegExp).join(".*") + "$");
          const protocol = url.protocol.slice(0, -1).toLowerCase();
          const hostname = url.hostname.toLowerCase();
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
            return globToRegExp(path).test(url.pathname + url.search);
          };
          if (!patterns.some(matches)) return;
          globalThis.chrome = {
            runtime: {
              sendMessage: (...args) => runtime.sendMessage(...args),
              connect: (...args) => runtime.connect(...args),
            },
          };
        })();
        """#
}
