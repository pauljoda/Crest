import Foundation
import WebKit

@MainActor
enum BrowserVisitedLinkStyler {
    nonisolated private static let maximumVisitedURLCount = 5_000
    private static let contentWorld = WKContentWorld.world(
        name: "com.pauldavis.crest.visited-links"
    )

    nonisolated static func supports(_ pageURL: URL) -> Bool {
        guard pageURL.scheme?.lowercased() == "https",
              pageURL.path == "/search",
              let host = pageURL.host()?.lowercased() else { return false }
        let labels = host.split(separator: ".").map(String.init)
        guard let googleIndex = labels.lastIndex(of: "google") else { return false }
        let prefix = labels[..<googleIndex]
        let suffixCount = labels.distance(from: labels.index(after: googleIndex), to: labels.endIndex)
        return (prefix.isEmpty || prefix.allSatisfy { $0 == "www" })
            && (1...2).contains(suffixCount)
    }

    nonisolated static func normalizedVisitedURLStrings(
        _ history: [BrowserHistoryEntry]
    ) -> [String] {
        Array(
            history
                .compactMap { BrowserHistoryURL.normalized($0.url)?.absoluteString }
                .prefix(maximumVisitedURLCount)
        )
    }

    static func apply(
        history: [BrowserHistoryEntry],
        to webView: WKWebView
    ) async {
        guard let pageURL = webView.url, supports(pageURL) else { return }
        let visitedURLs = normalizedVisitedURLStrings(history)
        guard !visitedURLs.isEmpty else { return }
        _ = try? await webView.callAsyncJavaScript(
            script,
            arguments: ["visitedURLs": visitedURLs],
            in: nil,
            contentWorld: contentWorld
        )
    }

    private static let script = #"""
        const normalized = (rawValue) => {
          try {
            const url = new URL(rawValue, document.baseURI);
            if (url.hostname.endsWith('.google.com') && url.pathname === '/url') {
              const destination = url.searchParams.get('q') || url.searchParams.get('url');
              if (destination) return normalized(destination);
            }
            if (url.protocol !== 'http:' && url.protocol !== 'https:') return null;
            url.hash = '';
            return url.href;
          } catch (_) {
            return null;
          }
        };

        const identityKeys = (rawValue) => {
          const exact = normalized(rawValue);
          if (!exact) return [];
          const keys = [exact];
          const queryless = new URL(exact);
          const isGoogleSearch = queryless.pathname === '/search'
            && (queryless.hostname === 'google.com'
              || queryless.hostname.startsWith('google.')
              || queryless.hostname.startsWith('www.google.'));
          if (queryless.pathname !== '/' && !isGoogleSearch) {
            queryless.search = '';
            keys.push(queryless.href);
          }
          return keys;
        };

        globalThis.__crestVisitedURLs = new Set(
          visitedURLs.flatMap(identityKeys)
        );
        const paintVisitedResults = () => {
          for (const link of document.querySelectorAll('a[href]')) {
            const visited = identityKeys(link.href).some(
              (key) => globalThis.__crestVisitedURLs.has(key)
            );
            if (!visited) continue;
            const title = link.querySelector('h3') || link;
            title.style.setProperty('color', '#b88cff', 'important');
            title.style.setProperty('-webkit-text-fill-color', '#b88cff', 'important');
          }
        };

        paintVisitedResults();
        if (!globalThis.__crestVisitedObserver) {
          globalThis.__crestVisitedObserver = new MutationObserver(paintVisitedResults);
          globalThis.__crestVisitedObserver.observe(document.documentElement, {
            childList: true,
            subtree: true
          });
        }
        return true;
        """#
}
