import CryptoKit
import Foundation
import Security

/// The paired session: its identifier and the AES-128-GCM key both sides
/// derived from the six-digit code. It lives in memory only, for as long as the
/// helper process and the pairing do.
struct ApplePasswordsSecretSession: Sendable {
    // MARK: - Static Variables

    static let nonceLength = 16
    private static let tagLength = 16
    private static let keyLength = 16

    // MARK: - Variables

    /// The session identifier (`TID`) every encrypted message names.
    let identity: String
    let byteEncoding: ApplePasswordsByteEncoding
    private let key: SymmetricKey

    // MARK: - Initializers

    /// - Parameter sharedKey: The 32-byte SRP key. The cipher uses its first 16 bytes.
    init(identity: String, sharedKey: Data, byteEncoding: ApplePasswordsByteEncoding) {
        self.identity = identity
        self.byteEncoding = byteEncoding
        key = SymmetricKey(data: sharedKey.prefix(Self.keyLength))
    }

    // MARK: - Actions - Sealing

    /// Outbound layout: ciphertext, tag, nonce.
    /// - Parameter nonce: Fixed only by tests; a fresh random nonce otherwise.
    func seal(_ plaintext: Data, nonce: Data? = nil) throws -> Data {
        let nonceBytes = try nonce ?? Self.randomNonce()
        let box = try AES.GCM.seal(plaintext, using: key, nonce: AES.GCM.Nonce(data: nonceBytes))
        return box.ciphertext + box.tag + nonceBytes
    }

    /// Inbound layout: nonce, ciphertext, tag. The two layouts differ on purpose.
    func open(_ sealed: Data) throws -> Data {
        guard sealed.count >= Self.nonceLength + Self.tagLength else { throw ApplePasswordsError.malformedReply }
        let bytes = Array(sealed)
        let nonce = bytes[..<Self.nonceLength]
        let ciphertext = bytes[Self.nonceLength..<(bytes.count - Self.tagLength)]
        let tag = bytes[(bytes.count - Self.tagLength)...]
        do {
            let box = try AES.GCM.SealedBox(
                nonce: AES.GCM.Nonce(data: nonce),
                ciphertext: ciphertext,
                tag: tag
            )
            return try AES.GCM.open(box, using: key)
        } catch {
            throw ApplePasswordsError.malformedReply
        }
    }

    // MARK: - Actions - Messages

    /// The sealed message that carries `body` to the helper.
    func message(sealing body: some Encodable) throws -> ApplePasswordsSealedMessage {
        let sealed = try seal(JSONEncoder().encode(body))
        return ApplePasswordsSealedMessage(
            sessionIdentifier: identity,
            sealedData: byteEncoding.string(for: sealed, prefixed: true)
        )
    }

    /// The decoded body of a message from the helper, once it names this session.
    func body<Body: Decodable>(of message: ApplePasswordsSealedMessage, as type: Body.Type) throws -> Body {
        guard message.sessionIdentifier == identity else { throw ApplePasswordsError.malformedReply }
        let plaintext = try open(try byteEncoding.bytes(from: message.sealedData))
        guard let body = try? JSONDecoder().decode(Body.self, from: plaintext) else {
            throw ApplePasswordsError.malformedReply
        }
        return body
    }

    // MARK: - Actions - Randomness

    static func randomBytes(count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else {
            throw ApplePasswordsError.randomnessUnavailable
        }
        return Data(bytes)
    }

    private static func randomNonce() throws -> Data {
        try randomBytes(count: nonceLength)
    }
}
