import Foundation

/// Stable accessibility identifiers derived from domain identity, never mutable
/// or localized display text.
enum BrowserAccessibilityID {

    static func identifier(prefix: String, id: UUID) -> String {
        "\(prefix)-\(id.uuidString.lowercased())"
    }

    static func urlIdentity(_ url: URL) -> String {
        var components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        )
        let scheme = components?.scheme?.lowercased()
        let host = components?.host?.lowercased()
        components?.scheme = scheme
        components?.host = host
        let identity = components?.string ?? url.absoluteString
        let allowed = CharacterSet(
            charactersIn:
                "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._"
        )
        guard
            let encoded = identity.addingPercentEncoding(
                withAllowedCharacters: allowed
            ), !encoded.isEmpty
        else {
            return "empty-url"
        }
        return encoded
    }
}
