import Foundation

actor PrivateBrowsingCredentialVault: CredentialVault {
    func descriptors(in spaceID: SpaceID) async throws -> [CredentialDescriptor] {
        []
    }

    func descriptors(
        matching origin: CredentialOrigin,
        in spaceID: SpaceID
    ) async throws -> [CredentialDescriptor] {
        []
    }

    func descriptors(
        matching protectionSpace: BrowserHTTPAuthenticationProtectionSpace,
        in spaceID: SpaceID
    ) async throws -> [CredentialDescriptor] {
        []
    }

    func credential(
        id: CredentialID,
        in spaceID: SpaceID
    ) async throws -> BrowserCredential? {
        nil
    }

    func save(_ credential: BrowserCredential, in spaceID: SpaceID) async throws {
        throw CredentialVaultError.unavailableInPrivateBrowsing
    }

    func replaceAll(_ credentials: [BrowserCredential], in spaceID: SpaceID) async throws {
        throw CredentialVaultError.unavailableInPrivateBrowsing
    }

    func setSynchronizable(_ isSynchronizable: Bool, in spaceID: SpaceID) async throws {
        throw CredentialVaultError.unavailableInPrivateBrowsing
    }

    func delete(id: CredentialID, in spaceID: SpaceID) async throws {}

    func deleteAll(in spaceID: SpaceID) async throws {}
}
