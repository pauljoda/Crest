import Foundation

/// Downloads the filter lists the core says are due, the catalog's and the ones
/// the person added, and hands each one back to the core, which keeps it,
/// converts it and decides when it is due again. The
/// updater only fetches, with the validators the core gives, so a list that has
/// not changed costs a conditional request. It asks when the app starts, every
/// hour while it runs, and whenever the lists change, so a list the person adds
/// or turns on arrives at once. It sends no cookies or stored credentials,
/// follows redirects to https addresses alone, and stops a download that
/// grows past what the core keeps.
@MainActor
final class BrowserFilterListUpdater {
    // MARK: - Types

    /// Follows a redirect only to another https address, so no one on the
    /// network can change a list on its way.
    private final class SecureRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping @Sendable (URLRequest?) -> Void
        ) {
            completionHandler(request.url?.scheme?.lowercased() == "https" ? request : nil)
        }
    }

    // MARK: - Static Variables

    private static let interval: Duration = .seconds(60 * 60)
    /// The most a list may hold, as the core keeps it
    /// (`FilterLibrary.MaximumListBytes`).
    nonisolated private static let maximumBytes = 15 * 1024 * 1024

    // MARK: - Variables

    private let core: CrestCore
    private let session: URLSession
    private var schedule: Task<Void, Never>?
    private var isChecking = false
    /// Whether a check came in while one ran.
    private var checksAgain = false

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

    /// Checks now, then every hour and whenever the lists change, until the
    /// updater goes away.
    func start() {
        guard schedule == nil else { return }
        schedule = Task { [weak self] in
            while !Task.isCancelled {
                await self?.check()
                try? await Task.sleep(for: Self.interval)
            }
        }
        checkWhenListsChange()
    }

    /// Checks again once the core's lists change, watching again first so a
    /// change during the check is not missed. The core answers only what is
    /// due, so a change a download made asks for nothing more.
    private func checkWhenListsChange() {
        withObservationTracking {
            _ = core.state.filterLists
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.schedule?.isCancelled == false else { return }
                self.checkWhenListsChange()
                await self.check()
            }
        }
    }

    /// Downloads each list due now, one at a time, and asks again when a check
    /// came in meanwhile.
    func check() async {
        guard !isChecking else {
            checksAgain = true
            return
        }
        isChecking = true
        defer { isChecking = false }
        repeat {
            checksAgain = false
            for fetch in (try? core.query(DueFilterDownloads())) ?? [] {
                await download(fetch)
            }
        } while checksAgain
    }

    // MARK: - Actions - Downloading

    private func download(_ fetch: FilterDownload) async {
        _ = try? core.send(await Self.outcome(of: fetch, in: session))
    }

    /// What the download of `fetch` brought, as the intent that tells the
    /// core. The body is read as it arrives, off the main actor, and given up
    /// once it grows past `maximumBytes`.
    nonisolated private static func outcome(of fetch: FilterDownload, in session: URLSession) async -> any Intent {
        guard let url = URL(string: fetch.url) else { return FilterDownloadFailed(id: fetch.id) }
        var request = URLRequest(url: url)
        if let entityTag = fetch.entityTag { request.setValue(entityTag, forHTTPHeaderField: "If-None-Match") }
        if let lastModified = fetch.lastModified {
            request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
        }
        do {
            let (bytes, response) = try await session.bytes(for: request, delegate: SecureRedirects())
            guard let response = response as? HTTPURLResponse else { return FilterDownloadFailed(id: fetch.id) }
            if response.statusCode == 304 { return FilterDownloadNotModified(id: fetch.id) }
            guard response.statusCode == 200 else { return FilterDownloadFailed(id: fetch.id) }
            if response.expectedContentLength > maximumBytes { return FilterDownloadTooLarge(id: fetch.id) }
            var data = Data()
            data.reserveCapacity(Int(min(max(response.expectedContentLength, 64 * 1024), Int64(maximumBytes))))
            for try await byte in bytes {
                guard data.count < maximumBytes else { return FilterDownloadTooLarge(id: fetch.id) }
                data.append(byte)
            }
            guard let text = String(data: data, encoding: .utf8) else { return FilterDownloadFailed(id: fetch.id) }
            return FilterDownloadFetched(
                id: fetch.id, text: text,
                entityTag: response.value(forHTTPHeaderField: "ETag"),
                lastModified: response.value(forHTTPHeaderField: "Last-Modified"))
        } catch {
            return FilterDownloadFailed(id: fetch.id)
        }
    }
}
