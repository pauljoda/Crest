import Foundation

@MainActor
struct LiveBrowserOnboardingDataAccessProvider:
    BrowserOnboardingDataAccessProviding
{
    func resolve(
        for application: BrowserImportApplication
    ) -> BrowserImportDataDirectoryAccess? {
        BrowserImportAccessStore.resolve(for: application)
    }

    func clear(for application: BrowserImportApplication) {
        BrowserImportAccessStore.clear(for: application)
    }

    func remember(
        _ directoryURL: URL,
        for application: BrowserImportApplication
    ) throws {
        try BrowserImportAccessStore.remember(
            directoryURL,
            for: application
        )
    }

    func chooseDataFolder(
        for application: BrowserImportApplication,
        completion: @escaping @MainActor (URL?) -> Void
    ) {
        BrowserImportFilePicker.chooseDataFolder(
            for: application,
            completion: completion
        )
    }

    func hasSavedAccess(for application: BrowserImportApplication) -> Bool {
        BrowserImportAccessStore.bookmarkData(for: application) != nil
    }
}
