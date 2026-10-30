import Foundation

/// Tells the helper the person picked a generated code, and reads the code
/// that is current now. The helper may ask for Touch ID first, so the request
/// waits far longer than the others.
struct ApplePasswordsFillOneTimeCodeRequest: ApplePasswordsEncryptedRequest {
    // MARK: - Types

    typealias Body = ApplePasswordsOneTimeCodesRequest.Body

    // MARK: - Variables

    let session: ApplePasswordsSecretSession
    let tabID: Int
    /// The frame's host, which the query is about.
    let host: String
    let frameURLs: ApplePasswordsFrameURLs
    /// The username of the row the person picked, when it has one.
    let username: String?
    /// The domain of the row the person picked.
    let domain: String?

    typealias Reply = String?

    var command: ApplePasswordsCommand { .didFillOneTimeCode }
    var queryID: ApplePasswordsQueryID { .didFillOneTimeCode }
    var timeout: Duration { .seconds(120) }
    var envelopeURL: String? { nil }
    var body: Body { Body(action: .search, frameURLs: frameURLs, username: username) }

    // MARK: - Actions - Decoding

    /// The current code of the one generated entry that is the row's own, as
    /// Apple's extension picks it: the same source, username and domain. A reply
    /// with none or several such entries, or whose entry does not belong to the
    /// frame, fills nothing.
    func reply(from result: ApplePasswordsQueryResult) throws -> String? {
        guard try result.status.requireAnswer() else { return nil }
        let matches = frameURLs.admitted(result.codes).filter {
            $0.source == .generated && $0.username == username && $0.domain == domain
        }
        guard matches.count == 1, let code = matches[0].code, !code.isEmpty else { return nil }
        return code
    }
}
