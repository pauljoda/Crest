import Foundation

/// Asks the helper to open the Passwords app on a site, as Apple's extension
/// does. It is not encrypted, has no reply, and works without a pairing, so it
/// is not a request.
struct ApplePasswordsLaunchPasswordsAppMessage {
    // MARK: - Actions - Encoding

    /// - Parameter origin: The origin of the page's frame, which the Passwords
    ///   app searches for. Only the origin is sent, never a path or query.
    /// - Throws: `insecureOrigin` for an origin that is not https.
    static func encoded(origin: CredentialOrigin) throws -> Data {
        guard origin.isSecure else { throw ApplePasswordsError.insecureOrigin }
        return try JSONEncoder().encode(
            Body(number: ApplePasswordsCommand.launchPasswordsApp.number, searchQueryURL: origin.description))
    }

    // MARK: - Types

    private struct Body: Encodable {
        let number: Int
        let searchQueryURL: String

        private enum CodingKeys: String, CodingKey {
            case number = "cmd"
            case searchQueryURL
        }
    }
}
