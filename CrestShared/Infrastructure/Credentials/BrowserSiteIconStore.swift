import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Saved logins' site icons, fetched once from each site itself: never through
/// another service, never with cookies, and never from an address on the
/// local network, whether a page names it, a redirect leads there or a name
/// resolves to it. Icons are kept in Crest's caches so lists don't ask again,
/// and a site without one isn't asked again this launch.
actor BrowserSiteIconStore {
    // MARK: - Static Variables

    static let shared = BrowserSiteIconStore()

    /// The most of a site's front page Crest reads looking for its icons.
    private static let maximumPageBytes = 512 * 1024
    /// The largest icon Crest keeps.
    private static let maximumIconBytes = 256 * 1024
    /// How long a kept icon stands before Crest asks the site again.
    private static let cacheLifetime: TimeInterval = 30 * 24 * 60 * 60
    /// The icon size Crest prefers among those a page declares, in pixels.
    private static let preferredPixels = 64
    /// Name endings that only ever mean a device on the person's own network.
    private static let localSuffixes = [".local", ".localhost", ".lan", ".home.arpa", ".internal", ".intranet"]

    // MARK: - Variables

    private let redirects = BrowserSiteIconRedirects()
    private var icons: [String: Data] = [:]
    private var missing: Set<String> = []
    private var loading: [String: Task<Data?, Never>] = [:]
    private let session: URLSession
    private let directory: URL?

    // MARK: - Initializers

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 20
        session = URLSession(configuration: configuration)
        directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appending(path: Bundle.main.bundleIdentifier ?? "Crest", directoryHint: .isDirectory)
            .appending(path: "SiteIcons", directoryHint: .isDirectory)
    }

    // MARK: - Actions - Icons

    /// The icon of `origin`'s site, or nil when it has none Crest can show or
    /// may not ask for.
    func icon(for origin: CredentialOrigin) async -> Data? {
        guard let site = Self.siteURL(of: origin) else { return nil }
        let key = "\(origin.scheme)_\(origin.host)_\(origin.port)"
        if let icon = icons[key] { return icon }
        if missing.contains(key) { return nil }
        if let pending = loading[key] { return await pending.value }
        let task = Task { await self.load(site, key: key) }
        loading[key] = task
        let icon = await task.value
        loading[key] = nil
        if let icon { icons[key] = icon } else { missing.insert(key) }
        return icon
    }

    /// The icon of the first of `origins` whose site has one, as a login
    /// saved for several sites shows.
    func icon(forFirstOf origins: [CredentialOrigin]) async -> Data? {
        for origin in origins {
            if let icon = await icon(for: origin) { return icon }
        }
        return nil
    }

    private func load(_ site: URL, key: String) async -> Data? {
        let file = directory?.appending(path: key)
        if let file, let kept = Self.kept(at: file) { return kept }
        for candidate in await candidates(for: site) {
            guard let (data, _) = await fetch(candidate, limit: Self.maximumIconBytes), Self.isRasterImage(data) else {
                continue
            }
            if let file, let directory {
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try? data.write(to: file, options: .atomic)
            }
            return data
        }
        return nil
    }

    /// The icons `site`'s front page declares, best first, then the site's
    /// `favicon.ico`.
    private func candidates(for site: URL) async -> [URL] {
        var found: [URL] = []
        if let (page, base) = await fetch(site, limit: Self.maximumPageBytes),
            let html = String(data: page, encoding: .utf8) ?? String(data: page, encoding: .isoLatin1)
        {
            found = Self.declaredIcons(in: html, base: base)
        }
        if let fallback = URL(string: "/favicon.ico", relativeTo: site)?.absoluteURL { found.append(fallback) }
        var seen = Set<URL>()
        return found.filter { seen.insert($0).inserted }
    }

    /// `url`'s body, if it answers with success in at most `limit` bytes, and
    /// the address it finally came from.
    private func fetch(_ url: URL, limit: Int) async -> (Data, URL)? {
        guard await Self.mayFetch(url) else { return nil }
        var request = URLRequest(url: url)
        request.httpShouldHandleCookies = false
        guard let (bytes, response) = try? await session.bytes(for: request, delegate: redirects),
            let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
            http.expectedContentLength <= Int64(limit)
        else { return nil }
        var data = Data()
        do {
            for try await byte in bytes {
                data.append(byte)
                if data.count > limit { return nil }
            }
        } catch {
            return nil
        }
        return (data, http.url ?? url)
    }

    // MARK: - Actions - Reading

    /// The front page of `origin`'s site, when Crest may ask it for an icon: a
    /// web address named by a public host, not an IP address or a name that
    /// only a local network knows.
    private static func siteURL(of origin: CredentialOrigin) -> URL? {
        guard origin.scheme == "https" || origin.scheme == "http" else { return nil }
        let host = origin.host.lowercased()
        guard namesPublicHost(host) else { return nil }
        var components = URLComponents()
        components.scheme = origin.scheme
        components.host = host
        let defaultPort = origin.scheme == "https" ? 443 : 80
        if origin.port != defaultPort { components.port = origin.port }
        components.path = "/"
        return components.url
    }

    /// Whether `host` is a name the public internet knows: dotted, with a
    /// letter, not an IP address and not a name only a local network knows.
    static func namesPublicHost(_ host: String) -> Bool {
        let host = host.lowercased()
        return host.contains(".") && !host.contains(":") && !localSuffixes.contains(where: { host.hasSuffix($0) })
            && host.rangeOfCharacter(from: CharacterSet.letters) != nil
            && !host.split(separator: ".").allSatisfy({ $0.allSatisfy(\.isNumber) })
    }

    /// Whether Crest may ask `url` for an icon: a web address on a public
    /// host whose every address is public, so neither a page's icon link nor
    /// a redirect can reach the local network.
    static func mayFetch(_ url: URL?) async -> Bool {
        guard let url, url.scheme == "https" || url.scheme == "http", let host = url.host(percentEncoded: false),
            namesPublicHost(host)
        else { return false }
        return await Task.detached { BrowserSiteIconAddress.allPublic(for: host) }.value
    }

    /// The icons a page's `<link>` tags declare, nearest the preferred size
    /// first. Vector icons are left out, since only images are kept.
    private static func declaredIcons(in html: String, base: URL) -> [URL] {
        let tags = html.matches(of: #/<link\b[^>]*>/#.ignoresCase()).map { String(html[$0.range]) }
        var icons: [(url: URL, pixels: Int)] = []
        for tag in tags {
            let attributes = attributes(of: tag)
            let relation = (attributes["rel"] ?? "").lowercased().split(separator: " ")
            guard relation.contains(where: { $0 == "icon" || $0.hasPrefix("apple-touch-icon") }),
                !relation.contains("mask-icon"), let href = attributes["href"], !href.isEmpty,
                !(attributes["type"] ?? "").lowercased().contains("svg"), !href.lowercased().hasSuffix(".svg"),
                let url = URL(string: href, relativeTo: base)?.absoluteURL,
                url.scheme == "https" || url.scheme == "http"
            else { continue }
            let declared = (attributes["sizes"] ?? "").lowercased().split(separator: " ")
                .compactMap { $0.split(separator: "x").first.flatMap { Int($0) } }.max()
            let isTouchIcon = relation.contains { $0.hasPrefix("apple-touch-icon") }
            icons.append((url, declared ?? (isTouchIcon ? 180 : 32)))
        }
        // The smallest icon at least as large as the preferred size, then the
        // largest of the smaller ones.
        return icons.sorted { left, right in
            let leftFits = left.pixels >= preferredPixels
            let rightFits = right.pixels >= preferredPixels
            if leftFits != rightFits { return leftFits }
            return leftFits ? left.pixels < right.pixels : left.pixels > right.pixels
        }.map(\.url)
    }

    /// A tag's attributes by lowercased name, quoted or not.
    private static func attributes(of tag: String) -> [String: String] {
        var attributes: [String: String] = [:]
        for match in tag.matches(of: #/([A-Za-z][\w:-]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/#) {
            let value = match.2 ?? match.3 ?? match.4 ?? ""
            attributes[match.1.lowercased()] = String(value).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return attributes
    }

    /// Whether `data` is a raster image ImageIO reads, such as PNG or ICO.
    private static func isRasterImage(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0,
            let type = CGImageSourceGetType(source).flatMap({ UTType($0 as String) })
        else { return false }
        return type.conforms(to: .image) && !type.conforms(to: .svg)
    }

    /// The icon kept at `file`, while it is fresh.
    private static func kept(at file: URL) -> Data? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
            let modified = attributes[.modificationDate] as? Date,
            Date.now.timeIntervalSince(modified) < cacheLifetime
        else { return nil }
        return try? Data(contentsOf: file)
    }
}
