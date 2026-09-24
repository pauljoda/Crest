/// How a window starts in the core's device: its identity, whether it keeps
/// its record across launches, the window it starts as when it has no record,
/// and what it shows first. Only a window over the session the core keeps in
/// its file keeps a record; elsewhere `saved` has no effect.
struct BrowserWindowOpening {
    var id = BrowserWindowID()
    var saved = false
    var copying: BrowserWindowID?
    var showingSpaceID: SpaceID?
    var showingTabs: [SpaceID: TabID] = [:]
    /// False keeps only the Space the window starts on, showing no tab.
    var restoresTabs = true
}
