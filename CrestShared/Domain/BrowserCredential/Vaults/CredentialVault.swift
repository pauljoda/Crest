import Foundation

protocol CredentialVault: Sendable {
    func descriptors(in spaceID: UUID) async throws -> [CredentialDescriptor]
    func descriptors(
        matching origin: CredentialOrigin,
        in spaceID: UUID
    ) async throws -> [CredentialDescriptor]
    func descriptors(
        matching protectionSpace: BrowserHTTPAuthenticationProtectionSpace,
        in spaceID: UUID
    ) async throws -> [CredentialDescriptor]
    /// How many of the Space's items no longer read back. The listings above
    /// leave them out, so the rest of the Space stays usable.
    func unreadableCredentialCount(in spaceID: UUID) async throws -> Int

    func credential(id: UUID, in spaceID: UUID) async throws -> BrowserCredential?
    func save(_ credential: BrowserCredential, in spaceID: UUID) async throws
    /// Replaces one Space's complete credential inventory as one logical mutation.
    /// Implementations restore the prior inventory if any replacement write fails.
    func replaceAll(_ credentials: [BrowserCredential], in spaceID: UUID) async throws
    func setSynchronizable(_ isSynchronizable: Bool, in spaceID: UUID) async throws
    func delete(id: UUID, in spaceID: UUID) async throws
    func deleteAll(in spaceID: UUID) async throws
    /// Removes the items `unreadableCredentialCount(in:)` counts.
    func deleteUnreadableCredentials(in spaceID: UUID) async throws
}

extension CredentialVault {
    // MARK: - Actions - Moving

    /// Saves every credential the Space `source` keeps into the Space
    /// `destination`'s, each with its identity, leaving the source's in place.
    /// Copying again after an interruption skips the credentials already
    /// copied, so it never replaces an edit made to a copy since.
    func copyAll(from source: UUID, to destination: UUID) async throws {
        let copied = Set(try await descriptors(in: destination).map(\.id))
        for descriptor in try await descriptors(in: source) where !copied.contains(descriptor.id) {
            guard let credential = try await credential(id: descriptor.id, in: source) else { continue }
            try await save(credential.moved(to: destination), in: destination)
        }
    }
}
