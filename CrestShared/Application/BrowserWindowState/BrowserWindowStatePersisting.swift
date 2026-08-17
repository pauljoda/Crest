protocol BrowserWindowStatePersisting: AnyObject, Sendable {
    func load(id: BrowserWindowID) -> BrowserWindowState?
    func save(_ state: BrowserWindowState)
    func remove(id: BrowserWindowID)
    func flushPendingSaves() async
}
