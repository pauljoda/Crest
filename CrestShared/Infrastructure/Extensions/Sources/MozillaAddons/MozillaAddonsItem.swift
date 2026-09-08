import Foundation

/// A single add-on detail page on addons.mozilla.org.
///
/// AMO always normalizes a detail URL to `/{locale}/{application}/addon/{slug}/`
/// before the document loads, so a URL that does not already have that exact
/// shape is not a detail page this browser is looking at and is refused.
struct BrowserMozillaAddonsItem: Equatable, Identifiable, Sendable {
    static let host = "addons.mozilla.org"

    private static let applications: Set<String> = ["firefox", "android"]
    private static let maximumLocaleLength = 12

    let slug: BrowserMozillaAddonSlug
    let locale: String
    let application: String
    let storeURL: URL

    var id: String { slug.rawValue }

    init?(url: URL) {
        guard url.scheme?.lowercased() == "https",
            url.host?.lowercased() == Self.host,
            url.port == nil,
            url.user == nil,
            url.password == nil
        else {
            return nil
        }
        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count == 4,
            Self.isLocale(components[0]),
            Self.applications.contains(components[1]),
            components[2] == "addon",
            let slug = BrowserMozillaAddonSlug(components[3])
        else {
            return nil
        }
        var canonical = URLComponents()
        canonical.scheme = "https"
        canonical.host = Self.host
        canonical.path =
            "/\(components[0])/\(components[1])/addon/\(slug.rawValue)/"
        guard let storeURL = canonical.url else { return nil }
        self.slug = slug
        locale = components[0]
        application = components[1]
        self.storeURL = storeURL
    }

    /// Accepts AMO's own locale segments — a language subtag, optionally with a
    /// region subtag, such as `en-US`, `de`, or `pt-BR`.
    private static func isLocale(_ value: String) -> Bool {
        guard !value.isEmpty,
            value.utf8.count <= maximumLocaleLength
        else {
            return false
        }
        let subtags = value.split(separator: "-", omittingEmptySubsequences: false)
        guard (1...2).contains(subtags.count) else { return false }
        return subtags.allSatisfy { subtag in
            !subtag.isEmpty
                && subtag.utf8.allSatisfy { byte in
                    (0x61...0x7a).contains(byte)
                        || (0x41...0x5a).contains(byte)
                        || (0x30...0x39).contains(byte)
                }
        }
    }
}
