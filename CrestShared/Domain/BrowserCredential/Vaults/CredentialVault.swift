import Foundation

protocol CredentialVault: Sendable {
    func descriptors(in spaceID: SpaceID) async throws -> [CredentialDescriptor]
    func descriptors(
        matching origin: CredentialOrigin,
        in spaceID: SpaceID
    ) async throws -> [CredentialDescriptor]
    func descriptors(
        matching protectionSpace: BrowserHTTPAuthenticationProtectionSpace,
        in spaceID: SpaceID
    ) async throws -> [CredentialDescriptor]

    func credential(id: CredentialID, in spaceID: SpaceID) async throws -> BrowserCredential?
    func save(_ credential: BrowserCredential, in spaceID: SpaceID) async throws
    /// Replaces one Space's complete credential inventory as one logical mutation.
    /// Implementations restore the prior inventory if any replacement write fails.
    func replaceAll(_ credentials: [BrowserCredential], in spaceID: SpaceID) async throws
    func setSynchronizable(_ isSynchronizable: Bool, in spaceID: SpaceID) async throws
    func delete(id: CredentialID, in spaceID: SpaceID) async throws
    func deleteAll(in spaceID: SpaceID) async throws
}
