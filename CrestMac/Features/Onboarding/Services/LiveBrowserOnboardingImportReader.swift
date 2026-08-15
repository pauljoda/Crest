import Foundation

struct LiveBrowserOnboardingImportReader: BrowserOnboardingImportReading {
    func read(
        _ payload: BrowserDetectedImportPayload
    ) async throws -> BrowserOnboardingImportReadOutput {
        let passwordCandidates =
            payload.application.supportsPasswordImport
            ? try await BrowserPasswordImportReader.candidates(
                from: payload.passwordStores,
                application: payload.application
            )
            : []
        try Task.checkCancellation()

        let imported = try await BrowserDetectedImportReader.read(payload)
        try Task.checkCancellation()

        return BrowserOnboardingImportReadOutput(
            payload: payload,
            imported: imported,
            passwordCandidates: passwordCandidates
        )
    }
}
