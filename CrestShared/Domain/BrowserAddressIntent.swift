import Foundation

enum BrowserAddressIntent: Equatable, Sendable {
    case open(URL)
    case search(query: String, provider: BrowserSearchProvider, url: URL)

    var url: URL {
        switch self {
        case .open(let url), .search(_, _, let url):
            url
        }
    }
}
