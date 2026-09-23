final class InMemoryBrowserWindowStatePersistence:
    BrowserWindowStatePersisting,
    @unchecked Sendable
{
    private var states: [BrowserWindowID: BrowserWindowState] = [:]

    func load(id: BrowserWindowID) -> BrowserWindowState? {
        states[id]
    }

    func loadAll() -> [BrowserWindowState] {
        Array(states.values)
    }

    func save(_ state: BrowserWindowState) {
        states[state.id] = state
    }

    func remove(id: BrowserWindowID) {
        states[id] = nil
    }
}
