import Foundation

enum BrowserCredentialScope: Codable, Equatable, Hashable, Sendable {
    case webForm
    case httpBasic(realm: String?)
    case httpDigest(realm: String?)

    var isHTTPAuthentication: Bool {
        switch self {
        case .webForm:
            false
        case .httpBasic, .httpDigest:
            true
        }
    }

    var settingsLabel: String? {
        switch self {
        case .webForm:
            nil
        case let .httpBasic(realm):
            Self.httpAuthenticationLabel(method: "HTTP Basic", realm: realm)
        case let .httpDigest(realm):
            Self.httpAuthenticationLabel(method: "HTTP Digest", realm: realm)
        }
    }

    private static func httpAuthenticationLabel(method: String, realm: String?) -> String {
        guard let realm, !realm.isEmpty else {
            return "\(method) authentication"
        }
        return "\(method) · Realm “\(realm)”"
    }
}
