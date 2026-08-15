@MainActor
protocol BrowserOnboardingImportCommitting {
    func prepare(
        plan: BrowserImportReviewPlan,
        application: BrowserImportApplication,
        payload: BrowserDetectedImportPayload?,
        passwordCountsBySourceSpace: [SpaceID: Int]
    ) async throws -> BrowserOnboardingPreparedImport

    func finalize(
        plan: BrowserImportReviewPlan,
        preparedImport: BrowserOnboardingPreparedImport,
        browser: BrowserStore
    ) async throws -> BrowserPasswordImportResult
}
