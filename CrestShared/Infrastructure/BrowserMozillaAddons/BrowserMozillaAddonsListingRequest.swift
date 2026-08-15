import Foundation

/// Builds the addons.mozilla.org public API request that resolves a listing.
///
/// The v5 detail endpoint answers with the add-on's identity plus the current
/// version's signed file, its size, and its SHA-256 digest.
enum BrowserMozillaAddonsListingRequest {
    static let host = BrowserMozillaAddonsItem.host

    /// Localized fields answer as a dictionary keyed by locale. Pinning one
    /// locale keeps the response small and its shape predictable.
    static let locale = "en-US"

    static func url(for slug: BrowserMozillaAddonSlug) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/api/v5/addons/addon/\(slug.rawValue)/"
        components.queryItems = [URLQueryItem(name: "lang", value: locale)]
        guard let url = components.url else {
            preconditionFailure("The fixed add-on listing URL is invalid.")
        }
        return url
    }
}
