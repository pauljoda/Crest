extension BrowserCommandPaletteResults {
    static func intentResult(
        query: BrowserCommandPaletteQuery,
        searchProvider: BrowserSearchProvider
    ) -> BrowserCommandPaletteIntentResult? {
        guard
            !query.isEmpty,
            let intent = AddressResolver.intent(
                query.text,
                searchProvider: searchProvider
            )
        else { return nil }

        switch intent {
        case .open(let url):
            let host =
                url.host()?.replacingOccurrences(of: "www.", with: "")
                ?? url.absoluteString
            return BrowserCommandPaletteIntentResult(
                result: BrowserCommandPaletteResult(
                    section: nil,
                    id: "intent-open",
                    title: "Open \(host)",
                    subtitle: url.absoluteString,
                    symbol: "globe",
                    trailing: "",
                    target: .url(url)
                ),
                url: url,
                isNavigation: true
            )
        case .search(let text, let provider, let url):
            return BrowserCommandPaletteIntentResult(
                result: BrowserCommandPaletteResult(
                    section: nil,
                    id: "intent-search",
                    title: "Search with \(provider.title)",
                    subtitle: text,
                    symbol: "magnifyingglass",
                    searchProvider: provider,
                    trailing: "",
                    target: .url(url)
                ),
                url: url,
                isNavigation: false
            )
        }
    }
}
