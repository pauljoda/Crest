import Foundation

/// An open tab Tidy may file, as the model reads it: the page's title and
/// where it is, without the query or fragment, which add noise and can carry
/// tokens.
struct TidyTabCandidate: Equatable, Sendable {
    // MARK: - Static Variables

    /// News, social, video, weather and sports sites, whose front pages are
    /// not part of anything the person is working on.
    private static let frontPageHosts = try! NSRegularExpression(
        pattern:
            "^(www\\.)?(nytimes|cnn|bbc|reuters|washingtonpost|theguardian|npr|news\\.ycombinator|reddit|x|twitter"
            + "|facebook|instagram|linkedin|youtube|twitch|tiktok|espn|nba|nfl|weather|accuweather|news\\.google)\\.")
    /// Chat, music, mail and calendar apps, whose front pages are tools rather
    /// than topics.
    private static let appHosts = try! NSRegularExpression(
        pattern:
            "^(www\\.)?(discord|slack|open\\.spotify|music\\.apple|music\\.youtube|mail\\.google|outlook\\.live"
            + "|calendar\\.google|web\\.whatsapp|messenger)\\.")
    private static let frontPagePaths: Set<String> = [
        "", "home", "feed", "news", "us", "uk", "world", "en", "explore", "trending", "latest", "login", "signin",
        "app", "browse", "mail", "mail/u/0", "calendar", "calendar/u/0/r",
    ]
    /// A separator between a page's name and its site's, such as " - " or " | ".
    private static let titleSeparator = try! NSRegularExpression(pattern: "(?<=\\s)[|\u{2013}-]+(?=\\s)")

    // MARK: - Variables

    let tabID: UUID
    let pageTitle: String
    let host: String
    let path: String

    /// The one line the model reads for this tab: its title, host and path.
    var modelDescription: String { "\(pageTitle) — \(host)\(path)" }

    /// The title without a short trailing site name: "Pad thai - Wikipedia"
    /// becomes "Pad thai". Stands in for keyphrases a tab does not have yet.
    var cleanedTitle: String {
        let title = pageTitle as NSString
        var parts: [String] = []
        var partStart = 0
        for match in Self.titleSeparator.matches(in: pageTitle, range: NSRange(location: 0, length: title.length)) {
            parts.append(title.substring(with: NSRange(location: partStart, length: match.range.location - partStart)))
            partStart = match.range.location + match.range.length
        }
        parts.append(title.substring(from: partStart))
        let leadingParts = parts.dropLast()
        guard parts.count > 1, leadingParts.joined(separator: " ").count > 5, parts[parts.count - 1].count < 20 else {
            return pageTitle
        }
        return leadingParts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// How many path components deep the page is; a site's root is 0.
    var pathDepth: Int { path.split(separator: "/").count }

    /// The front page of a news, social, video or weather site, or of a chat,
    /// mail, music or calendar app. Such a tab stays loose.
    var isLooseSiteFrontPage: Bool {
        let range = NSRange(location: 0, length: (host as NSString).length)
        let normalizedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        return Self.frontPagePaths.contains(normalizedPath)
            && (Self.frontPageHosts.firstMatch(in: host, range: range) != nil
                || Self.appHosts.firstMatch(in: host, range: range) != nil)
    }

    /// A site's root or one level down, or a sign-in page: the tabs whose
    /// keyphrases the model is most likely to invent, so Tidy checks them.
    var isNearSiteRoot: Bool {
        let address = (host + path).lowercased()
        return pathDepth <= 1 || address.contains("login") || address.contains("signin") || address.contains("sign-in")
            || host.hasPrefix("accounts.")
    }

    // MARK: - Initializers

    init(tabID: UUID, pageTitle: String, host: String, path: String) {
        self.tabID = tabID
        self.pageTitle = pageTitle
        self.host = host
        self.path = path
    }

    /// The candidate for a tab showing `address`, read for its host and path
    /// only. Nil for an address with no host.
    init?(tabID: UUID, pageTitle: String, address: URL) {
        guard let host = address.host() else { return nil }
        self.init(tabID: tabID, pageTitle: pageTitle, host: host, path: address.path())
    }
}
