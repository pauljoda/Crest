import Foundation

struct BrowserCommandActionPresentation: Equatable, Sendable {
    let title: String
    let subtitle: String
    let symbol: String
    let url: URL

    init?(query: String, searchProvider: BrowserSearchProvider) {
        guard
            let intent = AddressResolver.intent(
                query,
                searchProvider: searchProvider
            )
        else {
            return nil
        }
        url = intent.url
        switch intent {
        case .open(let url):
            let host =
                url.host()?.replacingOccurrences(of: "www.", with: "")
                ?? url.absoluteString
            title = "Open \(host)"
            subtitle = url.absoluteString
            symbol = "globe"
        case .search(let query, let provider, _):
            title = "Search with \(provider.title)"
            subtitle = query
            symbol = "magnifyingglass"
        }
    }
}
