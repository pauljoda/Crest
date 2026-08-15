import Foundation

extension BrowserStore: BrowserCredentialSuggestionLoading {
    func credentialSuggestions(
        for origin: CredentialOrigin,
        in spaceID: SpaceID
    ) async throws -> [CredentialDescriptor] {
        guard let url = URL(string: origin.description) else {
            throw CredentialVaultError.invalidOrigin
        }
        return try await credentialSuggestions(for: url, in: spaceID)
    }
}
