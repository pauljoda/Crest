import Foundation

/// Reads an installed browser's data for review: the core reads its profiles'
/// bookmarks, sessions and installed extensions away from the main thread, and the password stores
/// are counted where the browser keeps passwords Crest imports.
struct LiveBrowserOnboardingImportReader: BrowserOnboardingImportReading {
    let core: CrestCore

    func read(
        _ payload: BrowserDetectedImportPayload
    ) async throws -> BrowserOnboardingImportReadOutput {
        let passwordCandidates =
            payload.application.suppliesPasswords
            ? try await BrowserPasswordImportReader.candidates(
                from: payload.passwordStores,
                application: payload.application
            )
            : []
        try Task.checkCancellation()

        let query = ReadImport(source: payload.application, profiles: payload.profiles)
        let core = self.core
        let imported = try await Task.detached(priority: .userInitiated) { try core.query(query) }.value
        try Task.checkCancellation()

        return BrowserOnboardingImportReadOutput(
            payload: payload,
            imported: imported.spaces,
            passwordCandidates: passwordCandidates,
            extensions: imported.extensions
        )
    }
}
