import Foundation

/// An open tab Tidy may file, as the model reads it: the page's title and
/// where it is, without the query or fragment, which add noise and can carry
/// tokens. The whole address is kept apart, only to tell whether the page
/// changed while Tidy worked.
struct TidyTabCandidate: Equatable, Sendable {
    // MARK: - Static Variables

    /// The domains of news, social, video, weather and sports sites, whose
    /// front pages are not part of anything the person is working on, and of
    /// chat, music, mail and calendar apps, whose front pages are tools rather
    /// than topics. A host matches a domain or any of its subdomains.
    private static let looseFrontPageDomains: Set<String> = [
        "nytimes.com", "cnn.com", "bbc.com", "bbc.co.uk", "reuters.com", "washingtonpost.com", "theguardian.com",
        "npr.org", "news.ycombinator.com", "reddit.com", "x.com", "twitter.com", "facebook.com", "instagram.com",
        "linkedin.com", "youtube.com", "twitch.tv", "tiktok.com", "espn.com", "nba.com", "nfl.com", "weather.com",
        "accuweather.com", "news.google.com", "discord.com", "slack.com", "open.spotify.com", "music.apple.com",
        "mail.google.com", "outlook.live.com", "calendar.google.com", "web.whatsapp.com", "messenger.com",
    ]
    /// The paths of a site's front page, its sign-in page and the like.
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
    /// The tab's whole address, which the model never reads.
    private let address: String

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

    /// A site's front page, its sign-in page or the like, by its path.
    var isFrontPage: Bool {
        Self.frontPagePaths.contains(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased())
    }

    /// The front page of a news, social, video or weather site, or of a chat,
    /// mail, music or calendar app. Such a tab stays loose.
    var isLooseSiteFrontPage: Bool {
        let host = host.lowercased()
        return isFrontPage
            && Self.looseFrontPageDomains.contains { host == $0 || host.hasSuffix(".\($0)") }
    }

    /// A site's root or one level down, or a sign-in page: the tabs whose
    /// keyphrases the model is most likely to invent, so Tidy checks them.
    var isNearSiteRoot: Bool {
        let address = (host + path).lowercased()
        return pathDepth <= 1 || address.contains("login") || address.contains("signin") || address.contains("sign-in")
            || host.hasPrefix("accounts.")
    }

    // MARK: - Initializers

    /// The candidate for a tab showing `address`, which the model reads for
    /// its host and path only. Nil for an address with no host.
    init?(tabID: UUID, pageTitle: String, address: URL) {
        guard let host = address.host() else { return nil }
        self.tabID = tabID
        self.pageTitle = pageTitle
        self.host = host
        self.path = address.path()
        self.address = address.absoluteString
    }
}
