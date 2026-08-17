import Foundation

@MainActor
struct BrowserOnboardingPreviewDataAccessProvider:
    BrowserOnboardingDataAccessProviding
{
    func resolve(
        for application: BrowserImportApplication
    ) -> BrowserImportDataDirectoryAccess? {
        nil
    }

    func clear(for application: BrowserImportApplication) {}

    func remember(
        _ directoryURL: URL,
        for application: BrowserImportApplication
    ) throws {}

    func chooseDataFolder(
        for application: BrowserImportApplication,
        completion: @escaping @MainActor (URL?) -> Void
    ) {
        completion(nil)
    }

    func hasSavedAccess(for application: BrowserImportApplication) -> Bool {
        false
    }
}

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

struct BrowserOnboardingPreviewImportReader: BrowserOnboardingImportReading {
    func read(
        _ payload: BrowserDetectedImportPayload
    ) async throws -> BrowserOnboardingImportReadOutput {
        throw CancellationError()
    }
}

@MainActor
struct BrowserOnboardingPreviewSourceDiscovery:
    BrowserInstalledImportSourceDiscovering
{
    let sources: [BrowserInstalledImportSource]

    func installedSources() -> [BrowserInstalledImportSource] {
        sources
    }
}
