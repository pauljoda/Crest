struct BrowserHTTPAuthenticationSourcePolicy {
    static func label(
        host: String,
        port: Int,
        scheme: String?,
        emptyHostLabel: String
    ) -> String {
        guard !host.isEmpty else { return emptyHostLabel }
        guard !isDefault(port: port, for: scheme) else { return host }
        return "\(host):\(port)"
    }

    private static func isDefault(port: Int, for scheme: String?) -> Bool {
        switch scheme?.lowercased() {
        case "http":
            return port == 80
        case "https":
            return port == 443
        default:
            return false
        }
    }
}
