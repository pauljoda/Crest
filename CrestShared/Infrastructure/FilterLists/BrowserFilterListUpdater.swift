import Foundation

/// Downloads the filter lists the core says are due and hands each one back to
/// the core, which keeps it, converts it and decides when it is due again. The
/// updater only fetches, with the validators the core gives, so a list that has
/// not changed costs a conditional request. It asks when the app starts and
/// every hour while it runs, and sends no cookies or stored credentials.
@MainActor
final class BrowserFilterListUpdater {
    // MARK: - Variables

    private static let interval: Duration = .seconds(60 * 60)

    private let core: CrestCore
    private let session: URLSession
    private var schedule: Task<Void, Never>?
    private var isChecking = false

    // MARK: - Initializers

    init(core: CrestCore) {
        self.core = core
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 60
        session = URLSession(configuration: configuration)
    }

    // MARK: - Actions - Scheduling

    /// Checks now, then every hour until the updater goes away.
    func start() {
        guard schedule == nil else { return }
        schedule = Task { [weak self] in
            while !Task.isCancelled {
                await self?.check()
                try? await Task.sleep(for: Self.interval)
            }
        }
    }

    /// Downloads each list due now, one at a time.
    func check() async {
        guard !isChecking, let due = try? core.query(DueFilterListFetches()), !due.isEmpty else { return }
        isChecking = true
        defer { isChecking = false }
        for fetch in due {
            await download(fetch)
        }
    }

    // MARK: - Actions - Downloading

    private func download(_ fetch: FilterListFetch) async {
        guard let url = URL(string: fetch.url) else {
            _ = try? core.send(FilterListFetchFailed(list: fetch.list))
            return
        }
        var request = URLRequest(url: url)
        if let entityTag = fetch.entityTag { request.setValue(entityTag, forHTTPHeaderField: "If-None-Match") }
        if let lastModified = fetch.lastModified {
            request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
        }
        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            if response.statusCode == 304 {
                _ = try core.send(FilterListNotModified(list: fetch.list))
                return
            }
            guard response.statusCode == 200, let text = String(data: data, encoding: .utf8) else {
                throw URLError(.badServerResponse)
            }
            _ = try core.send(
                FilterListFetched(
                    list: fetch.list, text: text,
                    entityTag: response.value(forHTTPHeaderField: "ETag"),
                    lastModified: response.value(forHTTPHeaderField: "Last-Modified")))
        } catch {
            _ = try? core.send(FilterListFetchFailed(list: fetch.list))
        }
    }
}
