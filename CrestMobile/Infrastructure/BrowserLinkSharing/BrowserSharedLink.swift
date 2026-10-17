import Foundation

/// A web link shared to Crest from another app, with the Space the person
/// chose for it, if any. It reaches the app as a `crest://open` URL, or as a
/// saved entry when the extension could not open Crest.
///
/// The hand-off URL carries no more trust than an `https` link another app
/// opens: any app can build one, so it names only a web link and a Space,
/// and the app still routes the link and unlocks the Space as it would any
/// other.
struct BrowserSharedLink: Codable, Equatable, Sendable {
    // MARK: - Static Variables

    private static let handOffScheme = "crest"
    private static let handOffHost = "open"
    private static let urlParameter = "url"
    private static let spaceParameter = "space"
    private static let webSchemes: Set<String> = ["http", "https"]
    /// Characters a query value keeps unescaped, so `&`, `=` and `+` inside
    /// the shared link never split the hand-off's own parameters.
    private static let queryValueCharacters = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")

    // MARK: - Variables

    let url: URL
    let spaceID: UUID?

    /// The `crest://open` URL that hands this link to the app.
    var handOffURL: URL {
        var components = URLComponents()
        components.scheme = Self.handOffScheme
        components.host = Self.handOffHost
        var parameters = [Self.queryItem(Self.urlParameter, url.absoluteString)]
        if let spaceID {
            parameters.append(Self.queryItem(Self.spaceParameter, spaceID.uuidString))
        }
        components.percentEncodedQueryItems = parameters
        guard let handOffURL = components.url else {
            preconditionFailure("A crest://open URL with escaped parameters always forms.")
        }
        return handOffURL
    }

    // MARK: - Initializers

    /// A shared web link, or nil for anything but an `http` or `https` URL
    /// with a host.
    init?(url: URL, spaceID: UUID? = nil) {
        guard let scheme = url.scheme?.lowercased(), Self.webSchemes.contains(scheme),
            url.host(percentEncoded: false)?.isEmpty == false
        else { return nil }
        self.url = url
        self.spaceID = spaceID
    }

    /// The link a `crest://open` URL hands over, or nil for any other URL,
    /// for a link that is not a web link, and for a Space that is not an
    /// identifier.
    init?(handOffURL: URL) {
        guard handOffURL.scheme?.lowercased() == Self.handOffScheme,
            handOffURL.host(percentEncoded: false)?.lowercased() == Self.handOffHost,
            handOffURL.path().isEmpty || handOffURL.path() == "/",
            let parameters = URLComponents(url: handOffURL, resolvingAgainstBaseURL: false)?.queryItems,
            let linkValue = Self.value(of: Self.urlParameter, in: parameters),
            let url = URL(string: linkValue)
        else { return nil }
        var spaceID: UUID?
        if let spaceValue = Self.value(of: Self.spaceParameter, in: parameters) {
            guard let parsedSpaceID = UUID(uuidString: spaceValue) else { return nil }
            spaceID = parsedSpaceID
        }
        self.init(url: url, spaceID: spaceID)
    }

    // MARK: - Actions - Reading shared text

    /// The first web link in text another app shared, such as a note or a
    /// message, or nil when it holds none.
    static func firstWebLink(in text: String) -> BrowserSharedLink? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, range: range).lazy
            .compactMap(\.url)
            .compactMap { BrowserSharedLink(url: $0) }
            .first
    }

    /// The same link opening in `spaceID`.
    func opening(in spaceID: UUID?) -> BrowserSharedLink {
        BrowserSharedLink(verifiedURL: url, spaceID: spaceID)
    }

    // MARK: - Actions - Hand-off parameters

    private init(verifiedURL url: URL, spaceID: UUID?) {
        self.url = url
        self.spaceID = spaceID
    }

    private static func queryItem(_ name: String, _ value: String) -> URLQueryItem {
        URLQueryItem(
            name: name, value: value.addingPercentEncoding(withAllowedCharacters: queryValueCharacters))
    }

    /// The parameter's value, or nil when it is missing or given twice.
    private static func value(of name: String, in parameters: [URLQueryItem]) -> String? {
        let matches = parameters.filter { $0.name == name }
        guard matches.count == 1 else { return nil }
        return matches[0].value
    }
}
