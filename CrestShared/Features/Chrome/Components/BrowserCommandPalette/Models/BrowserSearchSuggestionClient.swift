import Foundation

/// Fetches an engine's search suggestions from the address the core names,
/// without cookies or caching.
actor BrowserSearchSuggestionClient {
    // MARK: - Static Variables

    static let shared = BrowserSearchSuggestionClient()
    static let maximumResponseByteCount = 64 * 1_024

    nonisolated static var sessionConfiguration: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 5
        return configuration
    }

    // MARK: - Variables

    private let session: URLSession

    // MARK: - Initializers

    init(session: URLSession? = nil) {
        self.session = session ?? URLSession(configuration: Self.sessionConfiguration)
    }

    // MARK: - Actions - Suggestions

    func suggestions(from address: URL) async throws -> [String] {
        var request = URLRequest(url: address)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        guard
            let response = response as? HTTPURLResponse,
            (200...299).contains(response.statusCode),
            response.expectedContentLength <= 0
                || response.expectedContentLength <= Self.maximumResponseByteCount
        else { return [] }

        var data = Data()
        data.reserveCapacity(min(Self.maximumResponseByteCount, 8 * 1_024))
        for try await byte in bytes {
            guard data.count < Self.maximumResponseByteCount else { return [] }
            data.append(byte)
        }
        return BrowserSearchSuggestionResponseParser.suggestions(from: data)
    }
}
