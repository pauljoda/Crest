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
