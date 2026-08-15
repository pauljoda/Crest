import Foundation

@MainActor
protocol BrowserCredentialSuggestionLoading: AnyObject {
    func credentialSuggestions(
        for origin: CredentialOrigin,
        in spaceID: SpaceID
    ) async throws -> [CredentialDescriptor]
}
