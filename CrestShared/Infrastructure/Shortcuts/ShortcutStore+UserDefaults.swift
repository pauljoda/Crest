import Foundation

extension BrowserShortcutStore {
    convenience init(
        defaults: UserDefaults,
        persistenceKey: String = UserDefaultsBrowserShortcutPersistence.currentKey,
        reset: Bool = false
    ) {
        self.init(
            persistence: UserDefaultsBrowserShortcutPersistence(
                defaults: defaults,
                persistenceKey: persistenceKey
            ),
            reset: reset
        )
    }
}
