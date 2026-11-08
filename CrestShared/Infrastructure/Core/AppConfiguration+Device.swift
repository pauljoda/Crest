import Foundation

extension AppConfiguration {
    /// A configuration for the device this process runs on, keeping the
    /// session in `storageDirectory`, or in memory when it is nil. An import
    /// names the Spaces it brings in the person's language, and the
    /// languages they read choose the regional filter lists. An isolated
    /// launch may name where the content filter's resources come from, to
    /// test a copy not yet published.
    init(storageDirectory: String?) {
        let launch = BrowserLaunchEnvironment.current
        self.init(
            storageDirectory: storageDirectory, platform: .current,
            importNames: ImportSource.all.compactMap(ImportSpaceNames.init(resolving:)),
            languages: Locale.preferredLanguages,
            filterResourcesURL: launch.requiresIsolation
                ? ProcessInfo.processInfo.environment["CREST_FILTER_RESOURCES_URL"] : nil)
    }
}
