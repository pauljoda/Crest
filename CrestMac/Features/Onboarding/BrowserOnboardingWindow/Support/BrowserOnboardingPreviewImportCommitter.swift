import Foundation

@MainActor
struct BrowserOnboardingPreviewImportCommitter:
    BrowserOnboardingImportCommitting
{
    func prepare(
        plan: BrowserImportReviewPlan,
        application: BrowserImportApplication,
        payload: BrowserDetectedImportPayload?,
        passwordCountsBySourceSpace: [SpaceID: Int]
    ) async throws -> BrowserOnboardingPreparedImport {
        throw CancellationError()
    }

    func finalize(
        plan: BrowserImportReviewPlan,
        preparedImport: BrowserOnboardingPreparedImport,
        browser: BrowserStore
    ) async throws -> BrowserPasswordImportResult {
        throw CancellationError()
    }
}
