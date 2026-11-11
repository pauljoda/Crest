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
        review: SetupImportReview,
        payload: BrowserDetectedImportPayload?
    ) async throws -> BrowserOnboardingPreparedImport {
        let directoryAccess = BrowserImportAccessStore.resolve(for: review.source)
        defer { directoryAccess?.stopAccessing() }

        let prepared: BrowserOnboardingPreparedImport
        do {
            let passwords = try await selectedPasswords(for: review, payload: payload)
            prepared = BrowserOnboardingPreparedImport(passwords: passwords)
        } catch is BrowserPasswordImportError {
            // Passwords that can't be read, as when the person denies the
            // Keychain, stay behind; the Spaces and tabs still come in.
            prepared = BrowserOnboardingPreparedImport(passwords: [], unreadPasswordCount: review.includedPasswordCount)
        }
        try Task.checkCancellation()
        return prepared
    }

    /// Imports the review's Spaces, then the passwords read for it, counting
    /// those that couldn't be read among the ones that couldn't be saved.
    func finalize(
        review: SetupImportReview,
        preparedImport: BrowserOnboardingPreparedImport,
        browser: BrowserStore
    ) async throws -> BrowserPasswordImportResult {
        try browser.importReviewedSpaces()
        let saved = await BrowserPasswordImportCommitter.commit(preparedImport.passwords, browser: browser)
        return BrowserPasswordImportResult(
            importedCount: saved.importedCount, skippedCount: saved.skippedCount,
            unsavedCount: saved.unsavedCount + preparedImport.unreadPasswordCount)
    }

    /// The passwords the review brings, read only when it brings any.
    private func selectedPasswords(
        for review: SetupImportReview,
        payload: BrowserDetectedImportPayload?
    ) async throws -> [BrowserImportedPassword] {
        guard let payload, review.includedPasswordCount > 0 else { return [] }
        return try await BrowserPasswordImportReader.read(
            from: payload.passwordStores,
            application: review.source,
            safeStorage: safeStorage
        )
    }
}
