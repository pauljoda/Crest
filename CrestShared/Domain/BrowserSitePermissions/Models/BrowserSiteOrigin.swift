import Foundation

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

    var displayName: String {
        guard !isDefaultPort else { return "\(scheme)://\(host)" }
        return "\(scheme)://\(host):\(port)"
    }

    private var isDefaultPort: Bool {
        (scheme == "http" && port == 80) || (scheme == "https" && port == 443)
    }
}
