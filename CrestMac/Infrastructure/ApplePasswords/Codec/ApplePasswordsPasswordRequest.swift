import Foundation

/// Reads the password for one username on one host. The helper may ask the
/// person for Touch ID first, so the request waits far longer than the others.
struct ApplePasswordsPasswordRequest: ApplePasswordsEncryptedRequest {
    // MARK: - Types

    struct Body: Encodable, Sendable {
        let action: ApplePasswordsQueryAction
        let host: String
        let username: String

        private enum CodingKeys: String, CodingKey {
            case action = "ACT"
            case host = "URL"
            case username = "USR"
        }
    }

    // MARK: - Variables

    let session: ApplePasswordsSecretSession
    let tabID: Int
    let host: String
    let username: String

    typealias Reply = String?

    var command: ApplePasswordsCommand { .getPassword }
    var queryID: ApplePasswordsQueryID { .password }
    var body: Body { Body(action: .search, host: host, username: username) }
    var timeout: Duration { .seconds(120) }

    // MARK: - Actions - Decoding

    /// The password of the entry for the username asked about whose sites
    /// include the frame's host, as Apple's own extension picks it. Never the
    /// first entry by position, and never an entry for another site.
    func reply(from result: ApplePasswordsQueryResult) throws -> String? {
        guard try result.status.requireAnswer(), !ApplePasswordsQueryResult.Entry.isNeverSaveMarker(username) else {
            return nil
        }
        return result.logins.first { $0.username == username && $0.sites.contains(host) }?.password
    }
}
