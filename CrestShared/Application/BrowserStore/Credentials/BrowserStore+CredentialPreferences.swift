import Foundation

extension BrowserStore {
    func updateCredentialPreferences(
        _ preferences: BrowserCredentialPreferences,
        in spaceID: SpaceID
    ) {
        guard session.space(id: spaceID) != nil else { return }
        session.updateCredentialPreferences(preferences, in: spaceID)
        persist(scope: .core)
    }

    func setCrestPasswordSynchronization(
        _ isSynchronizable: Bool,
        in spaceID: SpaceID
    ) async throws {
        guard let space = session.space(id: spaceID) else {
            throw CredentialVaultError.missingSpace
        }
        guard space.credentialPreferences.syncsCrestPasswordsWithICloud != isSynchronizable else {
            return
        }

        try await credentialVault.setSynchronizable(isSynchronizable, in: spaceID)
        var preferences = space.credentialPreferences
        preferences.syncsCrestPasswordsWithICloud = isSynchronizable
        session.updateCredentialPreferences(preferences, in: spaceID)
        persist(scope: .core)
    }

}
