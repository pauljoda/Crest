import Foundation

/// Opens pairing: sends Crest's public value and session identifier, and the
/// helper answers with its own public value and a salt, then shows a
/// six-digit code in its window.
struct ApplePasswordsClientHelloRequest: ApplePasswordsRequest {
    // MARK: - Static Variables

    /// The browser name the helper shows next to the code. The helper is known
    /// to accept this one; whether it accepts Crest's own name is untested.
    static let browserName = "Chrome"
    private static let queryID = "m0"
    private static let handshakeVersion = "1.0"
    /// The one handshake protocol Crest speaks: SRP with RFC verification.
    private static let protocolNumber = 1

    // MARK: - Types

    /// What the helper answers with, still to be checked against the group.
    struct ServerHello: Sendable {
        let publicKey: Data
        let salt: Data
    }

    private struct Hello: Encodable {
        let identity: String
        let stage: Int
        let publicKey: String
        let version: String
        let protocols: [Int]

        private enum CodingKeys: String, CodingKey {
            case identity = "TID"
            case stage = "MSG"
            case publicKey = "A"
            case version = "VER"
            case protocols = "PROTO"
        }
    }

    private struct Answer: Decodable {
        let identity: String
        let stage: ApplePasswordsLooseInteger?
        let negotiatedProtocol: ApplePasswordsLooseInteger?
        let publicKey: String?
        let salt: String?
        let errorCode: ApplePasswordsLooseInteger?

        private enum CodingKeys: String, CodingKey {
            case identity = "TID"
            case stage = "MSG"
            case negotiatedProtocol = "PROTO"
            case publicKey = "B"
            case salt = "s"
            case errorCode = "ErrCode"
        }
    }

    // MARK: - Variables

    let identity: String
    /// The minimal big-endian bytes of Crest's public value.
    let publicKey: Data
    let byteEncoding: ApplePasswordsByteEncoding

    var command: ApplePasswordsCommand { .handshake }

    // MARK: - Actions - Encoding

    func encoded() throws -> Data {
        let hello = Hello(
            identity: identity,
            stage: ApplePasswordsHandshakeStage.clientKeyExchange.number,
            publicKey: byteEncoding.string(for: publicKey, prefixed: true),
            version: Self.handshakeVersion,
            protocols: [Self.protocolNumber]
        )
        return try ApplePasswordsHandshakeEnvelope(queryID: Self.queryID, step: hello, browser: Self.browserName)
            .encoded()
    }

    // MARK: - Actions - Decoding

    /// Only a reply for this session identifier answers the request.
    func accepts(_ envelope: ApplePasswordsInboundEnvelope) -> Bool {
        (try? envelope.payload?.handshakeMessage(as: Answer.self))?.identity == identity
    }

    func reply(from envelope: ApplePasswordsInboundEnvelope) throws -> ServerHello {
        guard let payload = envelope.payload else { throw ApplePasswordsError.malformedReply }
        let answer = try payload.handshakeMessage(as: Answer.self)
        guard answer.identity == identity else { throw ApplePasswordsError.malformedReply }
        // An error code of zero is success, as in the proof's reply.
        if let code = answer.errorCode?.value, code != 0 { throw ApplePasswordsPairingError.rejected(code: code) }
        guard ApplePasswordsHandshakeStage.serverKeyExchange.isNamed(by: answer.stage),
            answer.negotiatedProtocol?.value == Self.protocolNumber,
            let publicKey = answer.publicKey, let salt = answer.salt
        else { throw ApplePasswordsError.malformedReply }
        // The salt stays the bytes the helper sent; a leading zero belongs to it.
        return ServerHello(
            publicKey: try byteEncoding.bytes(from: publicKey),
            salt: try byteEncoding.bytes(from: salt)
        )
    }
}
