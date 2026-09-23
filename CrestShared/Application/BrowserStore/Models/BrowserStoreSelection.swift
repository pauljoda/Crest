/// The one place a window's selection lives: the Space it shows and the tab it
/// shows in each Space. The core session carries browsing data only, so this is
/// never sent to it as state; commands read it as context and answer with a
/// `BrowserSelectionHint`. A Space without a selected tab shows nothing.
struct BrowserStoreSelection: Equatable, Sendable {
    // MARK: - Variables

    private(set) var selectedSpaceID: SpaceID
    private var selectedTabIDsBySpace: [SpaceID: TabID]

    /// Every Space's chosen tab, for window records and core command context.
    var tabSelections: [SpaceID: TabID] { selectedTabIDsBySpace }

    // MARK: - Initializers

    init(selectedSpaceID: SpaceID, selectedTabIDsBySpace: [SpaceID: TabID] = [:]) {
        self.selectedSpaceID = selectedSpaceID
        self.selectedTabIDsBySpace = selectedTabIDsBySpace
    }

    /// The launch selection for a session with no window record: the default
    /// Space, or the first one, showing its fallback tab.
    init(launching session: BrowserSession, excluding deletingSpaceIDs: Set<SpaceID> = []) {
        let available = session.spaces.filter { !deletingSpaceIDs.contains($0.id) }
        let launch = session.defaultSpaceID.flatMap { id in available.first { $0.id == id } } ?? available.first
        self.init(selectedSpaceID: launch?.id ?? session.spaces.first?.id ?? SpaceID())
        if let launch { ensureTab(in: launch) }
    }

    // MARK: - Actions - Selection

    func selectedTabID(in spaceID: SpaceID) -> TabID? {
        selectedTabIDsBySpace[spaceID]
    }

    func selectedSpace(in session: BrowserSession) -> BrowserSpace? {
        session.space(id: selectedSpaceID)
    }

    func selectedTab(in session: BrowserSession) -> BrowserTab? {
        guard let space = selectedSpace(in: session), let tabID = selectedTabIDsBySpace[space.id] else { return nil }
        return space.tabs.first { $0.id == tabID }
    }

    /// Shows a Space. One whose shown tab is gone, or that shows none, falls back
    /// to the core's fallback tab.
    mutating func selectSpace(_ space: BrowserSpace) {
        selectedSpaceID = space.id
        if let tabID = selectedTabIDsBySpace[space.id], space.contains(tabID) { return }
        ensureTab(in: space)
    }

    mutating func selectTab(_ tabID: TabID, in spaceID: SpaceID) {
        selectedSpaceID = spaceID
        selectedTabIDsBySpace[spaceID] = tabID
    }

    mutating func clearTab(in spaceID: SpaceID) {
        selectedTabIDsBySpace[spaceID] = nil
    }

    /// Applies what a command suggested. Tabs the session no longer holds are
    /// dropped by the reconciliation that follows every accepted change.
    mutating func apply(_ hint: BrowserSelectionHint) {
        for choice in hint.tabs { selectedTabIDsBySpace[choice.spaceID] = choice.tabID }
        if let spaceID = hint.spaceID { selectedSpaceID = spaceID }
    }

    /// Follows the session after any accepted change: forgets tabs and Spaces
    /// that are gone and moves off a Space that is gone or being deleted.
    mutating func reconcile(using shared: BrowserSession, excluding deletingSpaceIDs: Set<SpaceID>) {
        let availableSpaceIDs = Set(shared.spaces.map(\.id))
        selectedTabIDsBySpace = selectedTabIDsBySpace.filter { spaceID, tabID in
            shared.space(id: spaceID)?.contains(tabID) == true
        }
        guard !availableSpaceIDs.contains(selectedSpaceID) || deletingSpaceIDs.contains(selectedSpaceID) else { return }
        if let fallback = shared.spaces.first(where: { !deletingSpaceIDs.contains($0.id) }) {
            selectedSpaceID = fallback.id
            if selectedTabIDsBySpace[fallback.id] == nil { ensureTab(in: fallback) }
        }
    }

    /// The tab a Space shows when nothing chose one: the core's fallback, the
    /// first open tab, then the first pinned one, then the first tab. Nil for an
    /// empty Space or when the core cannot answer. Previews of Spaces that no
    /// window shows use this too.
    static func fallbackTabID(in space: BrowserSpace) -> TabID? {
        let candidates = [TabPlacement.current, .pinned, .saved]
            .compactMap { placement in space.tabs.firstIndex { $0.placement == placement } }
            .sorted()
        guard let chosen = BrowserCorePolicy.selectionFallback(placements: candidates.map { space.tabs[$0].placement })
        else { return nil }
        return space.tabs[candidates[chosen]].id
    }

    private mutating func ensureTab(in space: BrowserSpace) {
        selectedTabIDsBySpace[space.id] = Self.fallbackTabID(in: space)
    }
}
