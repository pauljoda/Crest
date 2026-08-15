import Foundation

enum BrowserSearchProvider: String, Codable, CaseIterable, Equatable, Hashable, Identifiable, Sendable {
    case google
    case duckDuckGo
    case bing
    case ecosia
    case brave

    var id: String { rawValue }

    var title: String {
        switch self {
        case .google: "Google"
        case .duckDuckGo: "DuckDuckGo"
        case .bing: "Bing"
        case .ecosia: "Ecosia"
        case .brave: "Brave Search"
        }
    }

    func searchURL(for query: String) -> URL? {
        let endpoint: String
        switch self {
        case .google:
            endpoint = "https://www.google.com/search"
        case .duckDuckGo:
            endpoint = "https://duckduckgo.com/"
        case .bing:
            endpoint = "https://www.bing.com/search"
        case .ecosia:
            endpoint = "https://www.ecosia.org/search"
        case .brave:
            endpoint = "https://search.brave.com/search"
        }

        var components = URLComponents(string: endpoint)
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        return components?.url
    }
}
