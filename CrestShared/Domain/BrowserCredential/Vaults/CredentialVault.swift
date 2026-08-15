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
    func setSynchronizable(_ isSynchronizable: Bool, in spaceID: SpaceID) async throws
    func delete(id: CredentialID, in spaceID: SpaceID) async throws
    func deleteAll(in spaceID: SpaceID) async throws
}
