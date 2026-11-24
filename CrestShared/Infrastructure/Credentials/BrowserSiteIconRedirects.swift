import Foundation

/// Follows a site icon request's redirect only to an address Crest may ask,
/// so a site can't send the request on to the local network.
final class BrowserSiteIconRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    // MARK: - Actions

    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        await BrowserSiteIconStore.mayFetch(request.url) ? request : nil
    }
}
