#if CREST_CHROMIUM_HOST
    import Foundation

    extension PageHistoryChanged {
        @MainActor func present(on engine: ChromiumEngine) {
            guard let page = engine.presentedPage(pageID) else { return }
            page.backHistory = Self.items(back)
            page.forwardHistory = Self.items(forward)
            page.canGoBack = !back.isEmpty
            page.canGoForward = !forward.isEmpty
        }

        /// The entries as the page's history menus list them, nearest first.
        private static func items(_ entries: [PageHistoryEntry]) -> [BrowserNavigationHistoryItem] {
            entries.prefix(BrowserNavigationHistoryItem.listedLimit).enumerated().compactMap { index, entry in
                guard let url = URL(string: entry.url) else { return nil }
                let title = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
                return BrowserNavigationHistoryItem(
                    depth: index + 1, title: title.isEmpty ? url.host() ?? url.absoluteString : title, url: url)
            }
        }
    }
#endif
