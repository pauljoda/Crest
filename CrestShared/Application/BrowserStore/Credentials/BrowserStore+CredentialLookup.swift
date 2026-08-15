import Foundation

extension BrowserStore {
    func credentialSuggestions(for url: URL) async throws -> [CredentialDescriptor] {
        guard let spaceID = selectedSpace?.id else {
            throw CredentialVaultError.missingSpace
        }
        return try await credentialSuggestions(for: url, in: spaceID)
    }

    func savedCredentialDescriptors(in spaceID: SpaceID) async throws -> [CredentialDescriptor] {
        guard session.space(id: spaceID) != nil else {
            throw CredentialVaultError.missingSpace
        }
        return try await credentialVault.descriptors(in: spaceID)
    }

    func credentialSuggestions(
        for url: URL,
        in spaceID: SpaceID
    ) async throws -> [CredentialDescriptor] {
        guard let space = session.space(id: spaceID) else {
            throw CredentialVaultError.missingSpace
        }
        guard space.credentialPreferences.isEnabled else { return [] }
        guard let origin = CredentialOrigin(url: url) else {
            throw CredentialVaultError.invalidOrigin
        }
        guard origin.isSecure else { return [] }
        return try await credentialVault.descriptors(matching: origin, in: spaceID)
    }

    func credential(id: CredentialID) async throws -> BrowserCredential? {
        guard let spaceID = selectedSpace?.id else {
            throw CredentialVaultError.missingSpace
        }
        return try await credential(id: id, in: spaceID)
    }

    func credential(id: CredentialID, in spaceID: SpaceID) async throws -> BrowserCredential? {
        guard session.space(id: spaceID) != nil else {
            throw CredentialVaultError.missingSpace
        }
        return try await credentialVault.credential(id: id, in: spaceID)
    }

    func httpAuthenticationCredential(
        for protectionSpace: BrowserHTTPAuthenticationProtectionSpace,
        in spaceID: SpaceID
    ) async throws -> BrowserCredential? {
        guard let space = session.space(id: spaceID) else {
            throw CredentialVaultError.missingSpace
        }
        guard space.credentialPreferences.isEnabled else { return nil }
        guard protectionSpace.origin.isSecure else { return nil }
        let descriptors = try await credentialVault.descriptors(
            matching: protectionSpace,
            in: spaceID
        )
        guard let descriptor = descriptors.max(
            by: BrowserCredentialRecencyPolicy.isLessRecent
        ) else {
            return nil
        }
        return try await credentialVault.credential(id: descriptor.id, in: spaceID)
    }
}
