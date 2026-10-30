import Foundation

/// Lists the one-time codes Apple Passwords holds for a frame. The values of
/// codes the helper generates are not worth filling here; the current one is
/// read after the pick. The helper may ask the person for Touch ID first, so
/// the request waits far longer than the others.
struct ApplePasswordsOneTimeCodesRequest: ApplePasswordsEncryptedRequest {
    // MARK: - Types

    /// The body of both code queries, which differ in their action only.
    struct Body: Encodable, Sendable {
        /// What the query says it is about.
        private static let type = "oneTimeCodes"

        let action: ApplePasswordsQueryAction
        let frameURLs: ApplePasswordsFrameURLs
        let username: String?

        private enum CodingKeys: String, CodingKey {
            case action = "ACT"
            case type = "TYPE"
            case frameURLs
            case username
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(action, forKey: .action)
            try container.encode(Self.type, forKey: .type)
            try container.encode(frameURLs, forKey: .frameURLs)
            try container.encodeIfPresent(username, forKey: .username)
        }
    }

    // MARK: - Variables

    let session: ApplePasswordsSecretSession
    let tabID: Int
    /// The frame's host, which the query is about.
    let host: String
    let frameURLs: ApplePasswordsFrameURLs
    let username: String?

    typealias Reply = [ApplePasswordsOneTimeCode]

    var command: ApplePasswordsCommand { .getOneTimeCodes }
    var queryID: ApplePasswordsQueryID { .oneTimeCodes }
    var timeout: Duration { .seconds(120) }
    /// A code query names no URL in its envelope; the origins travel in the sealed body.
    var envelopeURL: String? { nil }
    var body: Body { Body(action: .ghostSearch, frameURLs: frameURLs, username: username) }

    // MARK: - Actions - Decoding

    func reply(from result: ApplePasswordsQueryResult) throws -> [ApplePasswordsOneTimeCode] {
        guard try result.status.requireAnswer() else { return [] }
        return frameURLs.admitted(result.codes)
    }
}
