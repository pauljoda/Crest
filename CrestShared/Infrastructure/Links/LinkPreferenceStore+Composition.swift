import Foundation

extension BrowserLinkPreferenceStore {
    static let shared: BrowserLinkPreferenceStore = {
        let persistence: any BrowserLinkPreferencesPersisting =
            BrowserLaunchIsolationPolicy.requiresIsolation(.current)
            ? InMemoryBrowserLinkPreferencesPersistence()
            : UserDefaultsBrowserLinkPreferencesPersistence()
        return BrowserLinkPreferenceStore(persistence: persistence)
    }()

    convenience init(
        defaults: UserDefaults = .standard,
        persistenceKey: String = UserDefaultsBrowserLinkPreferencesPersistence.currentKey
    ) {
        self.init(
            persistence: UserDefaultsBrowserLinkPreferencesPersistence(
                defaults: defaults,
                persistenceKey: persistenceKey
            )
        )
    }
}
