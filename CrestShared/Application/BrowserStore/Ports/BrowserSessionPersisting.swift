protocol BrowserSessionPersisting: AnyObject, Sendable {
    func load() -> BrowserSession?
    func save(_ session: BrowserSession, scope: BrowserSessionSaveScope)
    func flushPendingSaves() async
}
