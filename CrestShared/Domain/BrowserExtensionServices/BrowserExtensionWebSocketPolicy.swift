import Foundation

/// Whether an extension's own content security policy permits a WebSocket
/// connection.
///
/// A brokered worker WebSocket leaves the WebContent process entirely, so
/// WebKit never sees the connection and cannot apply the extension's CSP to
/// it. Crest evaluates the same `connect-src` list itself, from the manifest
/// the package shipped, so a package that narrowed its own network reach keeps
/// that narrowing on this transport.
///
/// This is the extension author's declared intent, not a security boundary
/// against the extension: an extension page could open the same socket
/// natively. Where the CSP grammar is ambiguous for a `ws:`/`wss:` URL, the
/// evaluation therefore resolves in favor of connecting — see
/// `hostSourceMatches` for the one deliberate divergence from Chromium.
struct BrowserExtensionWebSocketPolicy: Equatable, Sendable {
    /// The `connect-src` source list, or `nil` when the manifest declared
    /// neither `connect-src` nor `default-src` and every `ws:`/`wss:` URL is
    /// therefore allowed.
    private let sources: [Source]?

    /// The policy an extension gets when its manifest says nothing: Chrome's
    /// default `extension_pages` policy constrains scripts and objects only,
    /// so any `ws:` or `wss:` destination is reachable.
    static let unrestricted = BrowserExtensionWebSocketPolicy(sources: nil)

    private init(sources: [Source]?) {
        self.sources = sources
    }

    /// The policy a package declared for its extension pages, which is the
    /// environment a background worker runs in.
    ///
    /// Manifest V3 spells this as `content_security_policy.extension_pages`.
    /// Manifest V2 spelled the whole value as a bare string, and that spelling
    /// is still read so a V2 package keeps its declared reach.
    static func extensionPagesPolicy(in manifest: [String: Any]) -> String? {
        switch manifest["content_security_policy"] {
        case let policy as String:
            policy
        case let policies as [String: Any]:
            policies["extension_pages"] as? String
        default:
            nil
        }
    }

    init(policy: String?) {
        guard let policy, !policy.isEmpty else {
            self.init(sources: nil)
            return
        }
        var connectSources: [String]?
        var defaultSources: [String]?
        for directive in policy.split(separator: ";") {
            let tokens = directive.split(whereSeparator: \.isWhitespace)
            guard let name = tokens.first else { continue }
            let values = tokens.dropFirst().map(String.init)
            switch name.lowercased() {
            case "connect-src":
                connectSources = values
            case "default-src":
                defaultSources = values
            default:
                continue
            }
        }
        guard let declared = connectSources ?? defaultSources else {
            self.init(sources: nil)
            return
        }
        // A list that is exactly `'none'` blocks everything. A `'none'` mixed
        // with real sources is meaningless and CSP ignores it, which the
        // `unmatchable` mapping below reproduces.
        if declared.count == 1, declared[0].lowercased() == "'none'" {
            self.init(sources: [])
            return
        }
        self.init(sources: declared.map(Source.init(expression:)))
    }

    /// Whether the extension may open a WebSocket to `url`.
    ///
    /// Non-`ws(s)` schemes are refused before the policy is consulted: this
    /// transport speaks the WebSocket protocol and nothing else, so a package
    /// whose CSP happens to allow `https:` still cannot use it to reach an
    /// ordinary HTTP endpoint.
    func allowsConnection(to url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
            scheme == "ws" || scheme == "wss"
        else {
            return false
        }
        guard let sources else { return true }
        return sources.contains { $0.matches(url, scheme: scheme) }
    }
}

extension BrowserExtensionWebSocketPolicy {
    private enum Source: Equatable, Sendable {
        case wildcard
        case scheme(String)
        case host(HostSource)
        /// `'self'`, which for an extension page is a `chrome-extension:`
        /// origin and therefore never a WebSocket destination.
        case selfOrigin
        /// Nonces, hashes, and keywords such as `'unsafe-inline'`: syntax that
        /// exists for other directives and can never match a URL.
        case unmatchable

        init(expression: String) {
            let expression = expression.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            if expression == "*" {
                self = .wildcard
                return
            }
            if expression.hasPrefix("'") {
                self =
                    expression.lowercased() == "'self'"
                    ? .selfOrigin
                    : .unmatchable
                return
            }
            if expression.hasSuffix(":"), !expression.contains("//") {
                self = .scheme(String(expression.dropLast()).lowercased())
                return
            }
            guard let host = HostSource(expression: expression) else {
                self = .unmatchable
                return
            }
            self = .host(host)
        }

        func matches(_ url: URL, scheme: String) -> Bool {
            switch self {
            case .wildcard:
                // CSP3 lets `*` stand for any network scheme, which `ws` and
                // `wss` both are.
                true
            case .scheme(let sourceScheme):
                BrowserExtensionWebSocketPolicy.schemePartMatches(
                    sourceScheme,
                    scheme: scheme
                )
            case .host(let source):
                source.matches(url, scheme: scheme)
            case .selfOrigin, .unmatchable:
                false
            }
        }
    }

    private struct HostSource: Equatable, Sendable {
        let scheme: String?
        let host: String
        let matchesSubdomains: Bool
        /// `nil` means "the scheme's default port"; `"*"` means any port.
        let port: String?
        let path: String?

        init?(expression: String) {
            var remainder = Substring(expression)
            var scheme: String?
            if let schemeRange = remainder.range(of: "://") {
                scheme = String(remainder[remainder.startIndex..<schemeRange.lowerBound])
                    .lowercased()
                remainder = remainder[schemeRange.upperBound...]
            }
            var path: String?
            if let pathIndex = remainder.firstIndex(of: "/") {
                path = String(remainder[pathIndex...])
                remainder = remainder[remainder.startIndex..<pathIndex]
            }
            var port: String?
            if let portIndex = remainder.lastIndex(of: ":") {
                port = String(remainder[remainder.index(after: portIndex)...])
                remainder = remainder[remainder.startIndex..<portIndex]
            }
            var host = String(remainder).lowercased()
            var matchesSubdomains = false
            if host.hasPrefix("*.") {
                matchesSubdomains = true
                host = String(host.dropFirst(2))
            }
            guard !host.isEmpty else { return nil }
            if let port, port != "*", Int(port) == nil { return nil }
            self.scheme = scheme
            self.host = host
            self.matchesSubdomains = matchesSubdomains
            self.port = port
            self.path = path
        }

        func matches(_ url: URL, scheme urlScheme: String) -> Bool {
            // A source that names no scheme matches any `ws:`/`wss:` URL.
            //
            // Chromium would compare the expression against the protected
            // resource's own scheme, which for an extension page is
            // `chrome-extension:` — so `connect-src localhost:8000` there
            // matches no WebSocket at all. Reproducing that would silently
            // break packages whose author plainly meant the socket, and this
            // evaluation exists to honor declared intent rather than to
            // confine code that could open the same socket from a page.
            if let scheme,
                !BrowserExtensionWebSocketPolicy.schemePartMatches(
                    scheme,
                    scheme: urlScheme
                )
            {
                return false
            }
            guard let urlHost = url.host?.lowercased() else { return false }
            if host != "*" {
                if matchesSubdomains {
                    guard urlHost == host || urlHost.hasSuffix("." + host)
                    else {
                        return false
                    }
                } else if urlHost != host {
                    return false
                }
            }
            let effectivePort =
                url.port
                ?? BrowserExtensionWebSocketPolicy.defaultPort(for: urlScheme)
            switch port {
            case nil:
                guard
                    effectivePort
                        == BrowserExtensionWebSocketPolicy.defaultPort(
                            for: urlScheme
                        )
                else {
                    return false
                }
            case "*":
                break
            case let declared?:
                guard Int(declared) == effectivePort else { return false }
            }
            guard let path, path != "/", !path.isEmpty else { return true }
            let urlPath = url.path.isEmpty ? "/" : url.path
            return path.hasSuffix("/")
                ? urlPath.hasPrefix(path)
                : urlPath == path
        }
    }

    /// Chromium's scheme-part matching, which upgrades in one direction only:
    /// `ws:` covers a secure socket, `wss:` never covers an insecure one, and
    /// `https:` covers no socket at all.
    private static func schemePartMatches(
        _ sourceScheme: String,
        scheme: String
    ) -> Bool {
        switch sourceScheme {
        case scheme:
            true
        case "http":
            scheme == "http" || scheme == "https"
        case "ws":
            scheme == "ws" || scheme == "wss" || scheme == "http"
                || scheme == "https"
        default:
            false
        }
    }

    private static func defaultPort(for scheme: String) -> Int {
        switch scheme {
        case "wss", "https":
            443
        default:
            80
        }
    }
}
