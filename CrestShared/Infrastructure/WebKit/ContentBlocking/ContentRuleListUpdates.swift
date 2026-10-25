import Foundation

/// Fetches data-only snapshots from Crest's reviewed source tree. This client
/// never uses a browser profile, cookies, credentials, referrers, or page URLs.
@MainActor
final class BrowserContentRuleListUpdates {
    // MARK: - Static Variables

    private static let maximumBytes = ContentRuleList.maximumArchiveBytes
    private static let refreshInterval: TimeInterval = 24 * 60 * 60
    private static let retryInterval: TimeInterval = 60 * 60
    private static let source = URL(
        string:
            "https://raw.githubusercontent.com/pauljoda/Crest/main/CrestCore/src/CrestCore/Contracts/ContentBlocking/ContentBlockingRules.json.gz"
    )

    // MARK: - Variables

    private let cacheURL: URL?
    private let session: URLSession
    private var lastSuccess: Date?
    private var lastAttempt: Date?
    private var isFetching = false

    // MARK: - Initializers

    init(cacheURL: URL?, session: URLSession? = nil) {
        self.cacheURL = cacheURL
        self.session = session ?? Self.makeSession()
        lastSuccess = cacheURL.flatMap {
            try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        }
    }

    // MARK: - Actions - Cache

    func cachedSnapshot() -> Data? {
        guard let cacheURL,
            let size = try? cacheURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
            size <= Self.maximumBytes
        else { return nil }
        return try? Data(contentsOf: cacheURL)
    }

    func discardCachedSnapshot() {
        if let cacheURL { try? FileManager.default.removeItem(at: cacheURL) }
        lastSuccess = nil
    }

    /// Called only after core validation and WebKit compilation both succeed.
    func accept(_ data: Data, now: Date = .now) throws {
        if let cacheURL {
            try FileManager.default.createDirectory(
                at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: cacheURL, options: .atomic)
        }
        lastSuccess = now
    }

    // MARK: - Actions - Refresh

    func downloadIfDue(now: Date = .now) async throws -> Data? {
        guard !isFetching,
            lastSuccess.map({ now.timeIntervalSince($0) >= Self.refreshInterval }) ?? true,
            lastAttempt.map({ now.timeIntervalSince($0) >= Self.retryInterval }) ?? true,
            let source = Self.source
        else { return nil }
        isFetching = true
        lastAttempt = now
        defer { isFetching = false }
        var request = URLRequest(url: source, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse,
            response.statusCode == 200,
            response.url == source,
            response.expectedContentLength <= Self.maximumBytes
        else { throw URLError(.badServerResponse) }
        var data = Data()
        for try await byte in bytes {
            guard data.count < Self.maximumBytes else { throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
        }
        try Task.checkCancellation()
        guard !data.isEmpty else { throw URLError(.zeroByteResource) }
        return data
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.allowsConstrainedNetworkAccess = false
        return URLSession(configuration: configuration)
    }
}
