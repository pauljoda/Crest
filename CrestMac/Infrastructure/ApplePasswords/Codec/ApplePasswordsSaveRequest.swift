import Foundation

/// Offers a login to Apple Passwords, which asks the person to confirm in its
/// own alert. The helper may acknowledge with an empty result, but only after
/// the person answers that alert, and may never acknowledge at all. Like
/// Apple's own extension, which ignores the reply, the request waits a few
/// seconds and then counts as sent; whether the person saved is not known.
struct ApplePasswordsSaveRequest: ApplePasswordsEncryptedRequest {
    // MARK: - Types

    struct Body: Encodable, Sendable {
        let action: ApplePasswordsQueryAction
        /// The three fields for an existing entry are empty: this is a new one.
        let existingURL = ""
        let existingUsername = ""
        let existingPassword = ""
        let newHost: String
        let newUsername: String
        let newPassword: String

        private enum CodingKeys: String, CodingKey {
            case action = "ACT"
            case existingURL = "URL"
            case existingUsername = "USR"
            case existingPassword = "PWD"
            case newHost = "NURL"
            case newUsername = "NUSR"
            case newPassword = "NPWD"
        }
    }

    // MARK: - Variables

    let session: ApplePasswordsSecretSession
    let tabID: Int
    let host: String
    let username: String
    let password: String
    /// The kind of form the login came from, which names the query.
    let form: ApplePasswordsFormKind

    typealias Reply = Void

    var command: ApplePasswordsCommand { .setPassword }
    var timeout: Duration { .seconds(3) }
    var silentReply: Void? { () }
    var queryID: ApplePasswordsQueryID { form.queryID }
    /// A save names no URL in its envelope; the site travels as `NURL` in the sealed body.
    var envelopeURL: String? { nil }
    var body: Body {
        Body(action: .maybeAdd, newHost: host, newUsername: username, newPassword: password)
    }

    // MARK: - Actions - Decoding

    func reply(from result: ApplePasswordsQueryResult) throws {
        _ = try result.status.requireAnswer()
    }
}
