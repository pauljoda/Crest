import Foundation

/// Finishes pairing: proves Crest derived the same key from the code the
/// person typed, and gets the helper's proof back.
struct ApplePasswordsClientVerificationRequest: ApplePasswordsRequest {
    // MARK: - Static Variables

    private static let queryID = "m2"
    /// The helper's error code for a code that does not match.
    private static let wrongCodeErrorCode = 1

    // MARK: - Types

    /// The helper's proof that it holds the same key.
    struct ServerVerification: Sendable {
        let proof: Data
    }

    private struct Verification: Encodable {
        let identity: String
        let stage: Int
        let proof: String

        private enum CodingKeys: String, CodingKey {
            case identity = "TID"
            case stage = "MSG"
            case proof = "M"
        }
    }

    private struct Answer: Decodable {
        let identity: String
        let stage: ApplePasswordsLooseInteger?
        let errorCode: ApplePasswordsLooseInteger?
        let proof: String?

        private enum CodingKeys: String, CodingKey {
            case identity = "TID"
            case stage = "MSG"
            case errorCode = "ErrCode"
            case proof = "HAMK"
        }
    }

    // MARK: - Variables

    let identity: String
    /// Crest's proof of the shared key.
    let clientProof: Data
    let byteEncoding: ApplePasswordsByteEncoding

    var command: ApplePasswordsCommand { .handshake }

    // MARK: - Actions - Encoding

    func encoded() throws -> Data {
        let verification = Verification(
            identity: identity,
            stage: ApplePasswordsHandshakeStage.clientVerification.number,
            proof: byteEncoding.string(for: clientProof, prefixed: false)
        )
        return try ApplePasswordsHandshakeEnvelope(queryID: Self.queryID, step: verification, browser: nil).encoded()
    }

    // MARK: - Actions - Decoding

    /// Only a reply for this session identifier answers the request.
    func accepts(_ envelope: ApplePasswordsInboundEnvelope) -> Bool {
        (try? envelope.payload?.handshakeMessage(as: Answer.self))?.identity == identity
    }

    func reply(from envelope: ApplePasswordsInboundEnvelope) throws -> ServerVerification {
        guard let payload = envelope.payload else { throw ApplePasswordsError.malformedReply }
        let answer = try payload.handshakeMessage(as: Answer.self)
        guard answer.identity == identity else { throw ApplePasswordsError.malformedReply }
        if let code = answer.errorCode?.value, code != 0 {
            throw code == Self.wrongCodeErrorCode
                ? ApplePasswordsPairingError.wrongCode
                : ApplePasswordsPairingError.rejected(code: code)
        }
        guard ApplePasswordsHandshakeStage.serverVerification.isNamed(by: answer.stage), let proof = answer.proof else {
            throw ApplePasswordsError.malformedReply
        }
        return ServerVerification(proof: try byteEncoding.bytes(from: proof))
    }
}
