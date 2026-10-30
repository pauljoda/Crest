import Foundation

/// Apple Passwords as a read-only credential vault. It lists the usernames
/// Apple has saved for a page's host and reads a password only after the person
/// picks that row.
///
/// Nothing is stored. Each listing issues fresh identifiers and remembers, for
/// this launch, which origin and username each stands for. A password is read
/// only for an identifier this vault issued, only for the origin it was issued
/// for, and is not kept after it is returned.
actor ApplePasswordsCredentialVault: CredentialVault {
    // MARK: - Static Variables

    /// How many issued identifiers are remembered; the oldest are forgotten first.
    private static let issuedLimit = 512

    // MARK: - Variables

    private let source: any ApplePasswordsCredentialSource
    /// The core's answer for a Space, asked afresh for every read. Nil means
    /// the core could not answer, which refuses the read.
    private let supportForSpace: @Sendable (UUID) async -> ApplePasswordsSupport?
    private var issued: [UUID: CredentialDescriptor] = [:]
    private var issuedOrder: [UUID] = []

    // MARK: - Initializers

    /// - Parameter support: Asks the core whether Apple Passwords may be used
    ///   in a Space now (`ApplePasswordsAvailability`). The vault never decides;
    ///   nil lists and reads nothing.
    init(
        source: any ApplePasswordsCredentialSource,
        support: @escaping @Sendable (UUID) async -> ApplePasswordsSupport?
    ) {
        self.source = source
        supportForSpace = support
    }

    // MARK: - Actions - Listing

    func descriptors(matching origin: CredentialOrigin, in spaceID: UUID) async throws -> [CredentialDescriptor] {
        try await descriptors(matching: origin, in: spaceID, tab: nil)
    }

    /// The suggestions for a page of the tab that asked, nil where nothing names one.
    func descriptors(
        matching origin: CredentialOrigin, in spaceID: UUID, tab: UUID?
    ) async throws -> [CredentialDescriptor] {
        guard origin.isSecure else { throw CredentialVaultError.insecureOrigin }
        guard let support = await supportForSpace(spaceID) else { throw ApplePasswordsError.notPermitted }
        // The never-save fact is not an account, so it never becomes a descriptor.
        let logins = try await source.logins(for: origin, tab: tab, support: support)
        return logins.usernames.map { username in
            let descriptor = CredentialDescriptor(spaceID: spaceID, origin: origin, username: username)
            remember(descriptor)
            return descriptor
        }
    }

    /// Apple Passwords is only asked about one host at a time, so there is no
    /// inventory of a Space to list.
    func descriptors(in spaceID: UUID) async throws -> [CredentialDescriptor] { [] }

    /// Apple Passwords holds website passwords only, not HTTP authentication.
    func descriptors(
        matching protectionSpace: BrowserHTTPAuthenticationProtectionSpace,
        in spaceID: UUID
    ) async throws -> [CredentialDescriptor] { [] }

    /// Nothing is read ahead of the person's pick, so nothing can fail to read back.
    func unreadableCredentialCount(in spaceID: UUID) async throws -> Int { 0 }

    // MARK: - Actions - Reading

    func credential(id: UUID, in spaceID: UUID) async throws -> BrowserCredential? {
        try await credential(id: id, in: spaceID, tab: nil)
    }

    /// Reads the row's password for the tab that picked it, nil where nothing names one.
    func credential(id: UUID, in spaceID: UUID, tab: UUID?) async throws -> BrowserCredential? {
        guard let descriptor = issued[id], descriptor.spaceID == spaceID else { return nil }
        guard let support = await supportForSpace(spaceID) else { throw ApplePasswordsError.notPermitted }
        let password = try await source.password(
            for: descriptor.origin,
            username: descriptor.username,
            tab: tab,
            support: support
        )
        return BrowserCredential(descriptor: descriptor, password: password)
    }

    // MARK: - Actions - Mutations

    /// Crest does not write to Apple Passwords here.
    func save(_ credential: BrowserCredential, in spaceID: UUID) async throws {
        throw CredentialVaultError.credentialManagerDisabled
    }

    func replaceAll(_ credentials: [BrowserCredential], in spaceID: UUID) async throws {
        throw CredentialVaultError.credentialManagerDisabled
    }

    func setSynchronizable(_ isSynchronizable: Bool, in spaceID: UUID) async throws {
        throw CredentialVaultError.preferenceUpdateFailed
    }

    func delete(id: UUID, in spaceID: UUID) async throws {
        throw CredentialVaultError.credentialManagerDisabled
    }

    /// Crest keeps nothing of Apple Passwords, so erasing a Space only forgets the identifiers issued for it.
    func deleteAll(in spaceID: UUID) async throws {
        let forgotten = issued.filter { $0.value.spaceID == spaceID }.keys
        for id in forgotten { forget(id) }
    }

    func deleteUnreadableCredentials(in spaceID: UUID) async throws {}

    // MARK: - Mutators

    /// The helper restarted, so no identifier issued over the old process stands.
    func forgetIssued() {
        issued = [:]
        issuedOrder = []
    }

    private func remember(_ descriptor: CredentialDescriptor) {
        issued[descriptor.id] = descriptor
        issuedOrder.append(descriptor.id)
        while issuedOrder.count > Self.issuedLimit {
            issued[issuedOrder.removeFirst()] = nil
        }
    }

    private func forget(_ id: UUID) {
        issued[id] = nil
        issuedOrder.removeAll { $0 == id }
    }
}
