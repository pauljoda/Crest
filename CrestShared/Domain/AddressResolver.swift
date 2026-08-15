import Foundation

enum AddressResolver {
    static func resolve(
        _ input: String,
        searchProvider: BrowserSearchProvider = .google
    ) -> URL? {
        intent(input, searchProvider: searchProvider)?.url
    }

    static func intent(
        _ input: String,
        searchProvider: BrowserSearchProvider = .google
    ) -> BrowserAddressIntent? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if let explicitURL = explicitURL(from: value) { return .open(explicitURL) }
        if let localhostURL = localhostURL(from: value) { return .open(localhostURL) }
        if let domainURL = domainURL(from: value) { return .open(domainURL) }
        guard let url = searchProvider.searchURL(for: value) else { return nil }
        return .search(query: value, provider: searchProvider, url: url)
    }

    private static func explicitURL(from value: String) -> URL? {
        guard let components = URLComponents(string: value) else { return nil }
        guard ["http", "https"].contains(components.scheme?.lowercased()) else { return nil }
        guard components.host != nil else { return nil }
        return components.url
    }

    private static func localhostURL(from value: String) -> URL? {
        guard !value.contains(where: \.isWhitespace) else { return nil }
        guard let components = URLComponents(string: "http://\(value)") else { return nil }
        guard components.host?.lowercased() == "localhost" else { return nil }
        return components.url
    }

    private static func domainURL(from value: String) -> URL? {
        guard !value.contains(where: \.isWhitespace), value.contains(".") else { return nil }
        guard let components = URLComponents(string: "https://\(value)") else { return nil }
        guard components.host != nil else { return nil }
        return components.url
    }
}
