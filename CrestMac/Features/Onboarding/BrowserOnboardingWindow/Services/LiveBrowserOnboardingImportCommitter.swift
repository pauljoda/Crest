@MainActor
struct LiveBrowserOnboardingImportCommitter:
    BrowserOnboardingImportCommitting
{
    private let safeStorage: any BrowserSafeStorageSecretProviding

    init(
        safeStorage: any BrowserSafeStorageSecretProviding =
            LaunchScopedBrowserSafeStorage()
    ) {
        self.safeStorage = safeStorage
    }

    func prepare(
        plan: BrowserImportReviewPlan,
        application: BrowserImportApplication,
        payload: BrowserDetectedImportPayload?,
        passwordCountsBySourceSpace: [SpaceID: Int]
    ) async throws -> BrowserOnboardingPreparedImport {
        let directoryAccess = BrowserImportAccessStore.resolve(for: application)
        defer { directoryAccess?.stopAccessing() }

        let passwords = try await selectedPasswords(
            for: plan,
            application: application,
            payload: payload,
            passwordCountsBySourceSpace: passwordCountsBySourceSpace
        )
        try Task.checkCancellation()
        return BrowserOnboardingPreparedImport(passwords: passwords)
    }

    func finalize(
        plan: BrowserImportReviewPlan,
        preparedImport: BrowserOnboardingPreparedImport,
        browser: BrowserStore
    ) async throws -> BrowserPasswordImportResult {
        try browser.commitReviewedImport(plan)
        return await BrowserPasswordImportCommitter.commit(
            preparedImport.passwords,
            plan: plan,
            browser: browser
        )
    }

    private func selectedPasswords(
        for plan: BrowserImportReviewPlan,
        application: BrowserImportApplication,
        payload: BrowserDetectedImportPayload?,
        passwordCountsBySourceSpace: [SpaceID: Int]
    ) async throws -> [BrowserImportedPassword] {
        guard let payload,
            plan.spaces.contains(where: {
                $0.includesPasswords
                    && passwordCountsBySourceSpace[$0.id, default: 0] > 0
            })
        else {
            return []
        }
        return try await BrowserPasswordImportReader.read(
            from: payload.passwordStores,
            application: application,
            safeStorage: safeStorage
        )
    }
}
