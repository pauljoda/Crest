protocol BrowserSessionPersisting: AnyObject, Sendable {
    func load() -> BrowserSession?
    func save(_ session: BrowserSession, scope: BrowserSessionSaveScope)
    func save(_ session: BrowserSession, scope: BrowserSessionSaveScope, checkpoint: any BrowserSessionCheckpoint)
    func flushPendingSaves() async
}

extension BrowserSessionPersisting {
    func save(_ session: BrowserSession, scope: BrowserSessionSaveScope, checkpoint: any BrowserSessionCheckpoint) {
        save(session, scope: scope)
    }
}
