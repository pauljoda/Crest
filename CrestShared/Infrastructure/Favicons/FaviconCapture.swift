import Foundation
import WebKit

@MainActor
enum BrowserFaviconCapture {
    nonisolated static let maximumByteCount = 128 * 1_024

    static func capture(from webView: WKWebView) async -> Data? {
        guard let pageURL = webView.url, isHTTPFamily(pageURL) else { return nil }

        let value = try? await webView.callAsyncJavaScript(
            script,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        let discovered = discovery(from: value, pageURL: pageURL)
        let cookies = await allCookies(
            in: webView.configuration.websiteDataStore.httpCookieStore
        )
        var manifestIcons: [URL] = []
        for manifestURL in discovered.manifestURLs {
            guard
                let manifestData = await downloadManifest(
                    manifestURL,
                    pageURL: pageURL,
                    cookies: cookies,
                    userAgent: discovered.userAgent
                )
            else { continue }
            manifestIcons.append(
                contentsOf: manifestIconURLs(
                    from: manifestData,
                    manifestURL: manifestURL
                )
            )
        }
        let fallbackURL = URL(string: "/favicon.ico", relativeTo: pageURL)?
            .absoluteURL
        let candidates = prioritizedCandidateURLs(
            discoveredIconURLs: discovered.iconURLs,
            manifestIconURLs: manifestIcons,
            fallbackURL: fallbackURL
        )

        var visited: Set<URL> = []
        for candidate in candidates where visited.insert(candidate).inserted {
            if let data = decodeDataURL(candidate.absoluteString) {
                if let renderableData = await renderableCandidateData(
                    data,
                    mimeType: dataURLMIMEType(candidate.absoluteString),
                    in: webView
                ) {
                    return renderableData
                }
                continue
            }
            if let downloadedCandidate = await downloadedCandidate(
                candidate,
                pageURL: pageURL,
                cookies: cookies,
                userAgent: discovered.userAgent
            ) {
                if let renderableData = await renderableCandidateData(
                    downloadedCandidate.data,
                    mimeType: downloadedCandidate.mimeType,
                    in: webView
                ) {
                    return renderableData
                }
            }
        }
        return nil
    }

    static func discovery(from value: Any?, pageURL: URL) -> BrowserFaviconDiscovery {
        guard let result = value as? [String: Any] else {
            return BrowserFaviconDiscovery(
                iconURLs: [],
                manifestURLs: [],
                userAgent: nil
            )
        }
        return BrowserFaviconDiscovery(
            iconURLs: resolvedIconURLs(
                result["icons"],
                relativeTo: pageURL
            ),
            manifestURLs: resolvedURLs(
                result["manifests"],
                relativeTo: pageURL
            ),
            userAgent: normalizedUserAgent(result["userAgent"] as? String)
        )
    }

    static func decodeDataURL(_ value: String) -> Data? {
        guard value.starts(with: "data:image/"),
            let separator = value.firstIndex(of: ",")
        else { return nil }

        let metadata = value[..<separator]
        guard metadata.hasSuffix(";base64") else { return nil }

        let payload = value[value.index(after: separator)...]
        guard payload.utf8.count <= ((maximumByteCount * 4 / 3) + 8),
            let data = Data(base64Encoded: String(payload)),
            !data.isEmpty,
            data.count <= maximumByteCount
        else { return nil }
        return data
    }

    static func downloadCandidate(
        _ iconURL: URL,
        pageURL: URL,
        cookies: [HTTPCookie],
        userAgent: String? = nil,
        session: URLSession = candidateSession
    ) async -> Data? {
        await downloadedCandidate(
            iconURL,
            pageURL: pageURL,
            cookies: cookies,
            userAgent: userAgent,
            session: session
        )?.data
    }

    static func rasterizedSVGData(
        _ data: Data,
        in webView: WKWebView,
        maximumPixelSize: Int = 128
    ) async -> Data? {
        guard !data.isEmpty, data.count <= maximumByteCount else { return nil }
        let pixelSize = min(
            max(1, maximumPixelSize),
            maximumRasterizedPixelSize
        )
        guard
            let value = try? await webView.callAsyncJavaScript(
                rasterizeSVGScript,
                arguments: [
                    "svgBase64": data.base64EncodedString(),
                    "maximumPixelSize": pixelSize,
                ],
                in: nil,
                contentWorld: .defaultClient
            ),
            let dataURL = value as? String
        else { return nil }
        return decodeDataURL(dataURL)
    }

    private static func downloadedCandidate(
        _ iconURL: URL,
        pageURL: URL,
        cookies: [HTTPCookie],
        userAgent: String?,
        session: URLSession = candidateSession
    ) async -> DownloadedCandidate? {
        guard isHTTPFamily(iconURL),
            let (data, response) = await download(
                iconURL,
                pageURL: pageURL,
                cookies: cookies,
                userAgent: userAgent,
                session: session,
                maximumByteCount: maximumByteCount,
                accept:
                    "image/avif,image/webp,image/png,image/svg+xml,image/*,*/*;q=0.5"
            ),
            response.mimeType?.lowercased().hasPrefix("image/") == true
                || response.mimeType?.lowercased() == "application/octet-stream"
        else { return nil }
        return DownloadedCandidate(data: data, mimeType: response.mimeType)
    }

    private static func renderableCandidateData(
        _ data: Data,
        mimeType: String?,
        in webView: WKWebView
    ) async -> Data? {
        guard isSVG(data, mimeType: mimeType) else { return data }
        return await rasterizedSVGData(data, in: webView)
    }

    private static func isSVG(_ data: Data, mimeType: String?) -> Bool {
        if mimeType?.lowercased() == "image/svg+xml" { return true }
        guard
            let prefix = String(data: data.prefix(2_048), encoding: .utf8)?
                .trimmingCharacters(
                    in: .whitespacesAndNewlines.union(
                        CharacterSet(charactersIn: "\u{feff}")
                    )
                )
                .lowercased()
        else { return false }
        return prefix.hasPrefix("<svg")
            || (prefix.hasPrefix("<?xml") && prefix.contains("<svg"))
    }

    private static func dataURLMIMEType(_ value: String) -> String? {
        guard value.starts(with: "data:"),
            let separator = value.firstIndex(of: ";")
        else { return nil }
        let start = value.index(value.startIndex, offsetBy: 5)
        return String(value[start..<separator]).lowercased()
    }

    private static func downloadManifest(
        _ manifestURL: URL,
        pageURL: URL,
        cookies: [HTTPCookie],
        userAgent: String?
    ) async -> Data? {
        guard isHTTPFamily(manifestURL),
            let (data, _) = await download(
                manifestURL,
                pageURL: pageURL,
                cookies: cookies,
                userAgent: userAgent,
                session: candidateSession,
                maximumByteCount: 1_024 * 1_024,
                accept: "application/manifest+json,application/json,*/*;q=0.5"
            )
        else { return nil }
        return data
    }

    private static func download(
        _ url: URL,
        pageURL: URL,
        cookies: [HTTPCookie],
        userAgent: String?,
        session: URLSession,
        maximumByteCount: Int,
        accept: String
    ) async -> (Data, HTTPURLResponse)? {
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: 12
        )
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue(pageURL.absoluteString, forHTTPHeaderField: "Referer")
        if let userAgent = normalizedUserAgent(userAgent) {
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        }
        if let cookieHeader = cookieHeader(for: url, cookies: cookies) {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }
        guard let (data, response) = try? await session.data(for: request),
            let response = response as? HTTPURLResponse,
            (200..<300).contains(response.statusCode),
            !data.isEmpty,
            data.count <= maximumByteCount
        else { return nil }
        return (data, response)
    }

    static func manifestIconURLs(
        from data: Data,
        manifestURL: URL
    ) -> [URL] {
        guard let object = try? JSONSerialization.jsonObject(with: data),
            let manifest = object as? [String: Any],
            let icons = manifest["icons"] as? [[String: Any]]
        else { return [] }
        return icons.enumerated().compactMap {
            index,
            icon -> ManifestIconCandidate? in
            guard let source = icon["src"] as? String,
                let url = URL(string: source, relativeTo: manifestURL)?.absoluteURL,
                isHTTPFamily(url)
            else { return nil }
            // Manifest-only maskable and monochrome assets are installation
            // resources, not general browser chrome. Their safe-zone padding or
            // single-color glyph can look broken when used as a tab favicon.
            // The Web App Manifest default is `any` when purpose is omitted.
            let purposes = Set(
                (icon["purpose"] as? String ?? "any")
                    .lowercased()
                    .split(whereSeparator: \.isWhitespace)
                    .map(String.init)
            )
            guard purposes.contains("any") else { return nil }
            let sizes = (icon["sizes"] as? String ?? "")
                .lowercased()
                .split(whereSeparator: \.isWhitespace)
            let maximumSize =
                sizes
                .compactMap { Int($0.split(separator: "x").first ?? "") }
                .max() ?? 0
            let type = (icon["type"] as? String)?.lowercased()
            let isScalable =
                sizes.contains("any")
                || type == "image/svg+xml"
                || url.pathExtension.lowercased() == "svg"
            return ManifestIconCandidate(
                url: url,
                isScalable: isScalable,
                maximumSize: maximumSize,
                documentOrder: index
            )
        }
        .sorted { first, second in
            if first.isScalable != second.isScalable {
                return first.isScalable
            }
            if first.maximumSize != second.maximumSize {
                return first.maximumSize > second.maximumSize
            }
            return first.documentOrder < second.documentOrder
        }
        .map(\.url)
    }

    static func prioritizedCandidateURLs(
        discoveredIconURLs: [URL],
        manifestIconURLs: [URL],
        fallbackURL: URL?
    ) -> [URL] {
        var visited: Set<URL> = []
        return (manifestIconURLs + discoveredIconURLs + [fallbackURL].compactMap { $0 })
            .filter { visited.insert($0).inserted }
    }

    private static func resolvedURLs(
        _ value: Any?,
        relativeTo pageURL: URL
    ) -> [URL] {
        guard let strings = value as? [String] else { return [] }
        var visited: Set<URL> = []
        return strings.compactMap { string in
            guard let url = URL(string: string, relativeTo: pageURL)?.absoluteURL,
                isHTTPFamily(url) || url.scheme?.lowercased() == "data",
                visited.insert(url).inserted
            else { return nil }
            return url
        }
    }

    private static func resolvedIconURLs(
        _ value: Any?,
        relativeTo pageURL: URL
    ) -> [URL] {
        guard let values = value as? [[String: Any]] else {
            return resolvedURLs(value, relativeTo: pageURL)
        }
        let candidates = values.enumerated().compactMap {
            index,
            value -> IconCandidate? in
            guard let source = value["url"] as? String,
                let url = URL(string: source, relativeTo: pageURL)?.absoluteURL,
                isHTTPFamily(url) || url.scheme?.lowercased() == "data"
            else { return nil }
            let relationships = Set(
                (value["rel"] as? String ?? "")
                    .lowercased()
                    .split(whereSeparator: \.isWhitespace)
                    .map(String.init)
            )
            let isTouchIcon =
                relationships.contains("apple-touch-icon")
                || relationships.contains("apple-touch-icon-precomposed")
            let isBrowserIcon =
                !isTouchIcon
                && (relationships.contains("icon")
                    || relationships.contains("shortcut"))
            let maximumSize =
                (value["sizes"] as? String ?? "")
                .split(whereSeparator: \.isWhitespace)
                .compactMap { size in
                    Int(size.split(separator: "x").first ?? "")
                }
                .max() ?? 0
            return IconCandidate(
                url: url,
                preference: isBrowserIcon ? 1 : 0,
                maximumSize: maximumSize,
                documentOrder: index
            )
        }
        .sorted { first, second in
            if first.preference != second.preference {
                return first.preference > second.preference
            }
            if first.maximumSize != second.maximumSize {
                return first.maximumSize > second.maximumSize
            }
            return first.documentOrder < second.documentOrder
        }
        var visited: Set<URL> = []
        return candidates.compactMap { candidate in
            visited.insert(candidate.url).inserted ? candidate.url : nil
        }
    }

    private static func cookieHeader(
        for url: URL,
        cookies: [HTTPCookie]
    ) -> String? {
        guard let host = url.host()?.lowercased() else { return nil }
        let matching = cookies.filter { cookie in
            BrowserSiteDataPolicy.matchesCookieDomain(cookie.domain, host: host)
                && (!cookie.isSecure || url.scheme?.lowercased() == "https")
                && url.path.hasPrefix(cookie.path)
        }
        return HTTPCookie.requestHeaderFields(with: matching)["Cookie"]
    }

    private static func allCookies(
        in cookieStore: WKHTTPCookieStore
    ) async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            cookieStore.getAllCookies { continuation.resume(returning: $0) }
        }
    }

    private static func isHTTPFamily(_ url: URL?) -> Bool {
        url?.scheme?.lowercased() == "https"
            || url?.scheme?.lowercased() == "http"
    }

    private static let script = #"""
        const links = Array.from(document.querySelectorAll('link[rel][href]'));
        const icons = links
            .map((link) => {
                const rel = (link.rel || '').toLowerCase().split(/\s+/);
                if (!rel.some((token) => token === 'icon' || token === 'shortcut' || token === 'apple-touch-icon' || token === 'apple-touch-icon-precomposed')) {
                    return null;
                }
                return {
                    url: link.href,
                    rel: link.rel || '',
                    sizes: link.sizes?.value || ''
                };
            })
            .filter(Boolean);
        const manifests = Array.from(
            document.querySelectorAll('link[rel~="manifest"][href]')
        ).map((link) => link.href);
        return {
            icons,
            manifests: [...new Set(manifests)],
            userAgent: navigator.userAgent || ''
        };
        """#

    private static func normalizedUserAgent(_ value: String?) -> String? {
        guard let value,
            !value.isEmpty,
            value.utf8.count <= 1_024,
            !value.contains("\r"),
            !value.contains("\n")
        else { return nil }
        return value
    }

    private static let rasterizeSVGScript = #"""
        const image = new Image();
        image.src = `data:image/svg+xml;base64,${svgBase64}`;
        await image.decode();
        const sourceWidth = Math.max(1, image.naturalWidth || maximumPixelSize);
        const sourceHeight = Math.max(1, image.naturalHeight || maximumPixelSize);
        const scale = maximumPixelSize / Math.max(sourceWidth, sourceHeight);
        const width = Math.max(1, Math.round(sourceWidth * scale));
        const height = Math.max(1, Math.round(sourceHeight * scale));
        const canvas = document.createElement('canvas');
        canvas.width = width;
        canvas.height = height;
        const context = canvas.getContext('2d');
        if (!context) {
            throw new Error('Canvas 2D context is unavailable');
        }
        context.drawImage(image, 0, 0, width, height);
        return canvas.toDataURL('image/png');
        """#

    private static let maximumRasterizedPixelSize = 512

    private static let candidateSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return URLSession(configuration: configuration)
    }()

    private struct DownloadedCandidate {
        let data: Data
        let mimeType: String?
    }

    private struct IconCandidate {
        let url: URL
        let preference: Int
        let maximumSize: Int
        let documentOrder: Int
    }

    private struct ManifestIconCandidate {
        let url: URL
        let isScalable: Bool
        let maximumSize: Int
        let documentOrder: Int
    }
}
