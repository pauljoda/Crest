import BigNum
import CryptoKit
import Foundation

/// Crest's side of the helper's SRP-6a exchange: the RFC 5054 3072-bit group,
/// generator 5 and SHA-256. The six-digit code the helper shows is the SRP
/// password and the session identifier is the SRP username.
///
/// Where interop breaks is padding. `A` and `B` travel and enter the proofs as
/// minimal big-endian bytes, `u` hashes them padded to the group's width, and
/// the shared key hashes the minimal bytes of `S`.
struct ApplePasswordsSRPClient {
    // MARK: - Static Variables

    /// The width of the group in bytes: RFC 5054's 3072-bit prime.
    static let groupLength = 384
    private static let privateKeyLength = 32
    private static let groupPrimeHexadecimal =
        "FFFFFFFFFFFFFFFFC90FDAA22168C234C4C6628B80DC1CD129024E088A67CC74020BBEA63B139B22514A08798E3404DDEF9519B3CD3A431B302B0A6DF25F14374FE1356D6D51C245E485B576625E7EC6F44C42E9A637ED6B0BFF5CB6F406B7EDEE386BFB5A899FA5AE9F24117C4B1FE649286651ECE45B3DC2007CB8A163BF0598DA48361C55D39A69163FA8FD24CF5F83655D23DCA3AD961C62F356208552BB9ED529077096966D670C354E4ABC9804F1746C08CA18217C32905E462E36CE3BE39E772C180E86039B2783A2EC07A28FB5C55DF06F4C52C9DE2BCBF6955817183995497CEA956AE515D2261898FA051015728E5A8AAAC42DAD33170D04507A33A85521ABDF1CBA64ECFB850458DBEF0A8AEA71575D060C7DB3970F85A6E1E4C7ABF5AE8CDB0933D71E8C94E04A25619DCEE3D2261AD2EE6BF12FFA06D98A0864D87602733EC86A64521F2B18177B200CBBE117577A615D6C770988C0BAD946E208E24FA074E5AB3143DB5BFCE0FD108E4B82D120A93AD2CAFFFFFFFFFFFFFFFF"

    // These are immutable once built and only ever read, so sharing them is safe.
    private static let prime: BigNum = {
        guard let prime = BigNum(hex: groupPrimeHexadecimal) else {
            preconditionFailure("The SRP group prime does not parse.")
        }
        precondition(prime.bytes.count == groupLength, "The SRP group prime is not 3072 bits.")
        return prime
    }()
    private static let generator = BigNum(5)
    private static let zero = BigNum(0)

    // MARK: - Variables

    /// The SRP username: the session identifier string, whose UTF-8 bytes are hashed.
    let identity: String
    /// `A`, as minimal big-endian bytes: what the helper is sent.
    let publicKey: Data
    private let privateKey: BigNum
    private let publicValue: BigNum

    // MARK: - Initializers

    /// - Parameters:
    ///   - identity: The session identifier.
    ///   - privateKey: 32 random bytes, read as a big-endian integer.
    init(identity: String, privateKey: Data) {
        let exponent = BigNum(bytes: privateKey)
        let value = Self.generator.power(exponent, modulus: Self.prime)
        self.identity = identity
        self.privateKey = exponent
        publicValue = value
        publicKey = Self.minimalBytes(of: value)
    }

    /// A client with a fresh random private key.
    static func generate(identity: String) throws -> ApplePasswordsSRPClient {
        ApplePasswordsSRPClient(
            identity: identity, privateKey: try ApplePasswordsSecretSession.randomBytes(count: privateKeyLength))
    }

    // MARK: - Actions - Validation

    /// Whether the helper's public value and salt can start an exchange: the
    /// value lies strictly between 0 and the prime, and the salt is not empty.
    static func accepts(serverPublicKey: Data, salt: Data) -> Bool {
        let value = BigNum(bytes: serverPublicKey)
        return !salt.isEmpty && zero < value && value < prime
    }

    // MARK: - Actions - Exchange

    /// Derives the shared key and both proofs from the helper's challenge.
    /// The salt stays the bytes the helper sent: a leading zero belongs to it.
    func solve(serverPublicKey: Data, salt: Data, code: String) throws -> ApplePasswordsSRPSolution {
        guard Self.accepts(serverPublicKey: serverPublicKey, salt: salt) else {
            throw ApplePasswordsPairingError.invalidChallenge
        }
        let prime = Self.prime
        let generator = Self.generator
        let serverValue = BigNum(bytes: serverPublicKey)
        let serverBytes = Self.minimalBytes(of: serverValue)

        // u = H(PAD(A) | PAD(B)); a zero u would let the code be bypassed.
        let scrambler = BigNum(bytes: Self.hash(Self.padded(publicKey), Self.padded(serverBytes)))
        guard isPositive(scrambler) else { throw ApplePasswordsPairingError.invalidChallenge }

        // k = H(N | PAD(g)); x = H(s | H(I ":" code)).
        let multiplier = BigNum(
            bytes: Self.hash(Self.minimalBytes(of: prime), Self.padded(Self.minimalBytes(of: generator)))
        )
        let credentialHash = Self.hash(Data("\(identity):\(code)".utf8))
        let exponentX = BigNum(bytes: Self.hash(salt, credentialHash))

        // S = (B - k * g^x)^(a + u * x) mod N, with the subtraction kept non-negative.
        let verifierTerm = multiplier.mul(generator.power(exponentX, modulus: prime), modulus: prime)
        let base = serverValue.sub(verifierTerm, modulus: prime)
        let secret = base.power(privateKey + scrambler * exponentX, modulus: prime)
        guard isPositive(secret) else { throw ApplePasswordsPairingError.invalidChallenge }
        let secretBytes = Self.minimalBytes(of: secret)
        let sessionKey = Self.hash(secretBytes)

        // M = H((H(N) xor H(PAD(g))) | H(I) | s | A | B | K); HAMK = H(A | M | K).
        let primeHash = Self.hash(Self.minimalBytes(of: prime))
        let generatorHash = Self.hash(Self.padded(Self.minimalBytes(of: generator)))
        let groupDigest = Data(zip(primeHash, generatorHash).map { $0 ^ $1 })
        let clientProof = Self.hash(
            groupDigest, Self.hash(Data(identity.utf8)), salt, publicKey, serverBytes, sessionKey
        )
        let expectedServerProof = Self.hash(publicKey, clientProof, sessionKey)

        return ApplePasswordsSRPSolution(
            scrambler: Self.minimalBytes(of: scrambler),
            multiplier: Self.minimalBytes(of: multiplier),
            privateExponent: Self.minimalBytes(of: exponentX),
            sharedSecret: secretBytes,
            sessionKey: sessionKey,
            clientProof: clientProof,
            expectedServerProof: expectedServerProof
        )
    }

    // MARK: - Actions - Encoding

    /// The big-endian bytes of `value` with no leading zero; zero is one zero byte.
    private static func minimalBytes(of value: BigNum) -> Data {
        let bytes = value.bytes
        return bytes.isEmpty ? Data([0]) : Data(bytes)
    }

    /// `bytes` padded on the left with zeros to the group's width.
    private static func padded(_ bytes: Data) -> Data {
        Data(count: max(0, groupLength - bytes.count)) + bytes.suffix(groupLength)
    }

    private static func hash(_ parts: Data...) -> Data {
        var hasher = SHA256()
        for part in parts { hasher.update(data: part) }
        return Data(hasher.finalize())
    }

    private func isPositive(_ value: BigNum) -> Bool {
        Self.zero < value
    }
}
