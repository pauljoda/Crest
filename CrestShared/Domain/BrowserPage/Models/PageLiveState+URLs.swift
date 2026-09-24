import Foundation

extension PageLiveState {
    // MARK: - Static Variables

    /// A page its engine has shown nothing in yet.
    static let blank = PageLiveState(
        url: nil, pendingURL: nil, title: "", isLoading: false, canGoBack: false, canGoForward: false,
        security: PageSecurity.none, failure: nil, media: [], address: nil)

    // MARK: - Variables

    /// The address of the document the page shows.
    var documentURL: URL? { url.flatMap(URL.init(string:)) }

    /// Where a navigation that has not committed is heading.
    var pendingNavigationURL: URL? { pendingURL.flatMap(URL.init(string:)) }

    /// The address the page shows the person, as the core resolved it.
    var displayURL: URL? { address.flatMap(URL.init(string:)) }
}
