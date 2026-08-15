/// Mirrors a session in memory. Private browsing persists through this, which is
/// how a private tab's favicon never reaches disk.
final class InMemoryBrowserSessionPersistence: BrowserSessionPersisting, @unchecked Sendable {
    private(set) var session: BrowserSession?
    /// The scope of every save, in order. Lets a test read back what a mutation
    /// claimed to change.
    private(set) var savedScopes: [BrowserSessionSaveScope] = []

    /// Nothing here is ever decoded, so nothing here can be unreadable. Kept so
    /// both session stores answer the same question a composition root asks after
    /// `load()`.
    var status: BrowserSessionPersistenceStatus { .ready }

    func load() -> BrowserSession? {
        session
    }

    func save(_ session: BrowserSession, scope: BrowserSessionSaveScope) {
        self.session = session
        savedScopes.append(scope)
    }
}
