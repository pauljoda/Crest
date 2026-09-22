import Foundation

enum AddressResolver {
    static func resolve(
        _ input: String,
        searchProvider: BrowserSearchProvider = .google
    ) -> URL? {
        intent(input, searchProvider: searchProvider)?.url
    }

    /// The portable core owns address resolution for every composition; the
    /// Swift fallback it replaced is gone, along with the private matchers only
    /// that branch called.
    static func intent(
        _ input: String,
        searchProvider: BrowserSearchProvider = .google
    ) -> BrowserAddressIntent? {
        BrowserCorePolicy.addressIntent(input, provider: searchProvider)
    }
}
