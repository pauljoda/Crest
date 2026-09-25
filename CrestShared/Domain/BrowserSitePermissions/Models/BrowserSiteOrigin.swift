import Foundation

/// TRANSITIONAL until S6: the platform's copy of the core's `SiteOrigin`,
/// which it becomes there. The trap in that move is that the generated
/// `SiteOrigin` has a memberwise initializer with this type's labels,
/// `(scheme:host:port:)`, that does not normalize, so a plain rename would
/// silently drop lowercasing and the default web port at every construction
/// site. The normalizing initializer needs a label of its own, and `Hashable`
/// and `Codable` must be written by hand, since Swift synthesizes neither in
/// an extension in another file. Until then an origin converts to and from the
/// core's at the core boundary, in `core` and `init(_:)` below.
struct BrowserSiteOrigin: Codable, Equatable, Hashable, Sendable {
    let scheme: String
    let host: String
    let port: Int

    init(scheme: String, host: String, port: Int) {
        self.scheme = scheme.lowercased()
        self.host = host.lowercased()
        if port > 0 {
            self.port = port
        } else {
            switch scheme.lowercased() {
            case "http":
                self.port = 80
            case "https":
                self.port = 443
            default:
                self.port = port
            }
        }
    }

    init?(url: URL) {
        guard let scheme = url.scheme?.lowercased(),
            let host = url.host()?.lowercased(),
            !host.isEmpty
        else {
            return nil
        }
        self.init(scheme: scheme, host: host, port: url.port ?? 0)
    }

    /// An origin the core normalized.
    init(_ origin: SiteOrigin) {
        self.init(scheme: origin.scheme, host: origin.host, port: origin.port)
    }

    /// The origin as the core's rules read it.
    var core: SiteOrigin {
        SiteOrigin(scheme: scheme, host: host, port: port)
    }

    var displayName: String {
        guard !isDefaultPort else { return "\(scheme)://\(host)" }
        return "\(scheme)://\(host):\(port)"
    }

    private var isDefaultPort: Bool {
        (scheme == "http" && port == 80) || (scheme == "https" && port == 443)
    }
}
