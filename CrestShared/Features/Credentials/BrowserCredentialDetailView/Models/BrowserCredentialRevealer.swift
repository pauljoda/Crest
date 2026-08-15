typealias BrowserCredentialRevealer =
    @MainActor (
        CredentialID,
        BrowserSpaceRuntimeAssignment,
        String
    ) async throws -> BrowserCredential
