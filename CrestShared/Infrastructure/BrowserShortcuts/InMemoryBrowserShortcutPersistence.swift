final class InMemoryBrowserShortcutPersistence: BrowserShortcutPersisting {
    private(set) var overrides: [String: BrowserShortcutOverride]?

    init(overrides: [String: BrowserShortcutOverride]? = nil) {
        self.overrides = overrides
    }

    func load() -> [String: BrowserShortcutOverride]? {
        overrides
    }

    func save(_ overrides: [String: BrowserShortcutOverride]) {
        self.overrides = overrides
    }

    func remove() {
        overrides = nil
    }
}
