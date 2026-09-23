protocol BrowserWindowStatePersisting: AnyObject, Sendable {
    func load(id: BrowserWindowID) -> BrowserWindowState?
    /// Every stored window record, for launch work that must respect what any
    /// window will show before one is on screen.
    func loadAll() -> [BrowserWindowState]
    func save(_ state: BrowserWindowState)
    func remove(id: BrowserWindowID)
    func flushPendingSaves() async
}
