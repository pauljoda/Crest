import Foundation

/// Lists the usernames Apple Passwords has saved for one host. No password
/// is read, and the sites the helper names beside each username are ignored.
struct ApplePasswordsLoginNamesRequest: ApplePasswordsEncryptedRequest {
    // MARK: - Types

    struct Body: Encodable, Sendable {
        let action: ApplePasswordsQueryAction
        let host: String

        private enum CodingKeys: String, CodingKey {
            case action = "ACT"
            case host = "URL"
        }
    }

    /// What Apple Passwords holds for a host.
    struct Logins: Equatable, Sendable {
        static let none = Logins(usernames: [], neverSaves: false)

        let usernames: [String]
        /// Apple reports that the person chose never to save passwords for this
        /// site. The marker is a fact about the site, never an account.
        let neverSaves: Bool
    }

    // MARK: - Variables

    let session: ApplePasswordsSecretSession
    let tabID: Int
    let host: String

    typealias Reply = Logins

    var command: ApplePasswordsCommand { .getLoginNames }
    var queryID: ApplePasswordsQueryID { .loginNames }
    var body: Body { Body(action: .ghostSearch, host: host) }

    // MARK: - Actions - Decoding

    func reply(from result: ApplePasswordsQueryResult) throws -> Logins {
        guard try result.status.requireAnswer() else { return .none }
        var seen = Set<String>()
        let usernames = result.logins.compactMap(\.username).filter { seen.insert($0).inserted }
        return Logins(usernames: usernames, neverSaves: result.neverSaves)
    }
}
