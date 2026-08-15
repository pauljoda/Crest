import Foundation

@MainActor
protocol BrowserOnboardingDataAccessProviding {
    func resolve(
        for application: BrowserImportApplication
    ) -> BrowserImportDataDirectoryAccess?

    func clear(for application: BrowserImportApplication)

    func remember(
        _ directoryURL: URL,
        for application: BrowserImportApplication
    ) throws

    func chooseDataFolder(
        for application: BrowserImportApplication,
        completion: @escaping @MainActor (URL?) -> Void
    )

    func hasSavedAccess(for application: BrowserImportApplication) -> Bool
}
