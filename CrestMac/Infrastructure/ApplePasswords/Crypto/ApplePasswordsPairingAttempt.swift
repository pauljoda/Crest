import Foundation

/// One challenge the helper issued and the secrets Crest holds for it. The
/// helper accepts a code only for its newest challenge and spends the challenge
/// on the first answer, right or wrong, so an attempt is used once and then dropped.
struct ApplePasswordsPairingAttempt {
    // MARK: - Static Variables

    /// A challenge older than this is treated as expired and issued again.
    static let lifetime: Duration = .seconds(180)
    private static let identityLength = 16

    // MARK: - Variables

    let identity: String
    let byteEncoding: ApplePasswordsByteEncoding
    private let client: ApplePasswordsSRPClient
    private let serverHello: ApplePasswordsClientHelloRequest.ServerHello
    private let issuedAt: ContinuousClock.Instant

    // MARK: - Initializers

    private init(
        client: ApplePasswordsSRPClient,
        byteEncoding: ApplePasswordsByteEncoding,
        serverHello: ApplePasswordsClientHelloRequest.ServerHello,
        issuedAt: ContinuousClock.Instant
    ) {
        identity = client.identity
        self.client = client
        self.byteEncoding = byteEncoding
        self.serverHello = serverHello
        self.issuedAt = issuedAt
    }

    // MARK: - Actions - Opening

    /// The first message of a new attempt: a fresh session identifier and private key.
    /// - Returns: The client, to be kept until the helper's challenge arrives.
    static func opening(byteEncoding: ApplePasswordsByteEncoding) throws -> (
        client: ApplePasswordsSRPClient, request: ApplePasswordsClientHelloRequest
    ) {
        let identityBytes = try ApplePasswordsSecretSession.randomBytes(count: identityLength)
        let identity = byteEncoding.string(for: identityBytes, prefixed: true)
        let client = try ApplePasswordsSRPClient.generate(identity: identity)
        let request = ApplePasswordsClientHelloRequest(
            identity: identity,
            publicKey: client.publicKey,
            byteEncoding: byteEncoding
        )
        return (client, request)
    }

    /// The attempt the helper's challenge starts, or an error if the challenge is unusable.
    static func answered(
        _ serverHello: ApplePasswordsClientHelloRequest.ServerHello,
        client: ApplePasswordsSRPClient,
        byteEncoding: ApplePasswordsByteEncoding,
        at now: ContinuousClock.Instant
    ) throws -> ApplePasswordsPairingAttempt {
        guard ApplePasswordsSRPClient.accepts(serverPublicKey: serverHello.publicKey, salt: serverHello.salt) else {
            throw ApplePasswordsPairingError.invalidChallenge
        }
        return ApplePasswordsPairingAttempt(
            client: client,
            byteEncoding: byteEncoding,
            serverHello: serverHello,
            issuedAt: now
        )
    }

    // MARK: - Actions - Answering

    func isLive(at now: ContinuousClock.Instant) -> Bool {
        issuedAt.duration(to: now) < Self.lifetime
    }

    /// The proof for the typed code, and what is needed to check the helper's.
    func answer(code: String) throws -> (
        request: ApplePasswordsClientVerificationRequest, solution: ApplePasswordsSRPSolution
    ) {
        let solution = try client.solve(
            serverPublicKey: serverHello.publicKey,
            salt: serverHello.salt,
            code: code
        )
        let request = ApplePasswordsClientVerificationRequest(
            identity: identity,
            clientProof: solution.clientProof,
            byteEncoding: byteEncoding
        )
        return (request, solution)
    }
}
