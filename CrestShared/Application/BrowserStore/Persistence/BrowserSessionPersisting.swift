protocol BrowserSessionPersisting: AnyObject, Sendable {
    func load() -> BrowserSession?
    /// The selection an earlier release stored inside the session, read once so
    /// a window without its own record can adopt it. Nil when there is none.
    func loadLegacySelection() -> BrowserLegacySessionSelection?
    func save(_ session: BrowserSession, scope: BrowserSessionSaveScope)
    func save(_ session: BrowserSession, scope: BrowserSessionSaveScope, checkpoint: any BrowserSessionCheckpoint)
    func flushPendingSaves() async
}

extension BrowserSessionPersisting {
    func loadLegacySelection() -> BrowserLegacySessionSelection? { nil }

    func save(_ session: BrowserSession, scope: BrowserSessionSaveScope, checkpoint: any BrowserSessionCheckpoint) {
        save(session, scope: scope)
    }
}
