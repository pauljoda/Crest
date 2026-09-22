import Foundation

/// Scene-owned browser selection and chrome restoration. It references the
/// authoritative session's Space and tab identities without duplicating any
/// profile or WebKit storage identity, so every native window can restore
/// independently while retaining the existing Space isolation boundary.
struct BrowserWindowState: Codable, Equatable, Identifiable, Sendable {
    let id: BrowserWindowID
    private(set) var selectedSpaceID: SpaceID
    private(set) var selectedTabIDsBySpace: [SpaceID: TabID]
    /// A captured Space without an entry above intentionally has no selected
    /// tab. Missing in older records, which retain their legacy fallback.
    private(set) var capturedSpaceIDs: Set<SpaceID>?
    private(set) var sidebarWidth: Double?
    private(set) var sidebarIsPresented: Bool?

    /// Column width shares for the split groups this window has resized,
    /// keyed by group.
    ///
    /// Widths are a property of a window on a device, not of the browsing
    /// state: two windows showing the same group keep their own columns, and
    /// nothing here ever reaches a sync payload. The field is optional so a
    /// state written before Split View existed still decodes — the synthesized
    /// `Codable` conformance decodes a missing optional as `nil` — and so a
    /// window that has never been resized adds no key at all.
    private(set) var splitColumnFractionsByGroup: [SplitGroupID: [Double]]?

    init(
        id: BrowserWindowID = BrowserWindowID(),
        selectedSpaceID: SpaceID,
        selectedTabIDsBySpace: [SpaceID: TabID],
        sidebarWidth: Double? = nil,
        sidebarIsPresented: Bool? = nil,
        splitColumnFractionsByGroup: [SplitGroupID: [Double]]? = nil
    ) {
        self.id = id
        self.selectedSpaceID = selectedSpaceID
        self.selectedTabIDsBySpace = selectedTabIDsBySpace
        self.sidebarWidth = sidebarWidth
        self.sidebarIsPresented = sidebarIsPresented
        self.splitColumnFractionsByGroup = splitColumnFractionsByGroup
    }

    init(id: BrowserWindowID = BrowserWindowID(), restoring session: BrowserSession) {
        self.init(
            id: id,
            selectedSpaceID: session.selectedSpaceID,
            selectedTabIDsBySpace: Dictionary(
                uniqueKeysWithValues: session.spaces.compactMap { space in
                    guard let tabID = space.selectedTabID else { return nil }
                    return (space.id, tabID)
                }
            )
        )
        capturedSpaceIDs = Set(session.spaces.map(\.id))
        repair(using: session)
    }

    func selectedSpace(in session: BrowserSession) -> BrowserSpace? {
        session.space(id: selectedSpaceID)
    }

    func selectedTab(in session: BrowserSession) -> BrowserTab? {
        guard let space = selectedSpace(in: session),
            let tabID = selectedTabIDsBySpace[space.id]
        else { return nil }
        return space.tabs.first { $0.id == tabID }
    }

    mutating func selectSpace(_ spaceID: SpaceID, session: BrowserSession) {
        guard session.space(id: spaceID) != nil else { return }
        selectedSpaceID = spaceID
        repair(using: session)
    }

    mutating func selectTab(_ tabID: TabID, in spaceID: SpaceID, session: BrowserSession) {
        guard let space = session.space(id: spaceID), space.contains(tabID) else { return }
        selectedSpaceID = spaceID
        selectedTabIDsBySpace[spaceID] = tabID
        capturedSpaceIDs?.insert(spaceID)
    }

    mutating func captureSelection(from session: BrowserSession) {
        selectedSpaceID = session.selectedSpaceID
        selectedTabIDsBySpace = Dictionary(
            uniqueKeysWithValues: session.spaces.compactMap { space in
                guard let tabID = space.selectedTabID else { return nil }
                return (space.id, tabID)
            }
        )
        capturedSpaceIDs = Set(session.spaces.map(\.id))
        repair(using: session)
    }

    mutating func captureSidebar(
        width: Double? = nil,
        isPresented: Bool? = nil
    ) {
        if let width, width.isFinite, width > 0 {
            sidebarWidth = width
        }
        if let isPresented {
            sidebarIsPresented = isPresented
        }
    }

    /// Records one split group's column fractions for this window. The core
    /// decides whether the list describes columns and normalizes its sum; a
    /// list it rejects, or cannot answer for, is ignored.
    mutating func captureSplitLayout(fractions: [Double], for groupID: SplitGroupID) {
        guard let normalized = BrowserCorePolicy.splitColumnFractions(fractions) else { return }
        var fractionsByGroup = splitColumnFractionsByGroup ?? [:]
        fractionsByGroup[groupID] = normalized
        splitColumnFractionsByGroup = fractionsByGroup
    }

    func splitColumnFractions(for groupID: SplitGroupID) -> [Double]? {
        splitColumnFractionsByGroup?[groupID]
    }

    /// Reconciles this window with the session through the core's window-state
    /// rules: selections the session no longer holds fall back, captured empty
    /// Spaces stay empty, and column fractions a group can no longer use are
    /// forgotten. When the core cannot answer, the state is left untouched.
    mutating func repair(using session: BrowserSession) {
        let stored = splitColumnFractionsByGroup ?? [:]
        var liveMembers: [SplitGroupID: Int] = [:]
        if !stored.isEmpty {
            for space in session.spaces {
                for groupID in space.liveSplitGroupIDs where stored[groupID] != nil {
                    liveMembers[groupID] = space.splitGroupMembers(of: groupID).count
                }
            }
        }
        let facts = session.spaces.map { space in
            BrowserCorePolicy.WindowSpaceFacts(
                id: space.id,
                hasWindowTab: selectedTabIDsBySpace[space.id].map(space.contains) == true,
                isCaptured: capturedSpaceIDs?.contains(space.id) == true,
                hasSpaceSelection: space.selectedTabID.map(space.contains) == true,
                hasTabs: !space.tabs.isEmpty)
        }
        guard let repair = BrowserCorePolicy.windowRepair(
            selectedSpaceID: selectedSpaceID, sessionSelectedSpaceID: session.selectedSpaceID,
            capturesSelection: capturedSpaceIDs != nil, spaces: facts,
            splitLayouts: stored.map { groupID, fractions in
                BrowserCorePolicy.WindowSplitLayout(groupID: groupID, columns: fractions.count, liveMembers: liveMembers[groupID])
            })
        else { return }
        var selections: [SpaceID: TabID] = [:]
        for (space, selection) in zip(session.spaces, repair.selections) {
            switch selection {
            case .window: selections[space.id] = selectedTabIDsBySpace[space.id]
            case .space: selections[space.id] = space.selectedTabID
            case .first: selections[space.id] = space.tabs.first?.id
            case .none: break
            }
        }
        selectedTabIDsBySpace = selections
        capturedSpaceIDs = repair.capturedSpaceIDs.map { Set($0.map(SpaceID.init(rawValue:))) }
        let live = stored.filter { repair.splitLayoutGroupIDs.contains($0.key.rawValue) }
        splitColumnFractionsByGroup = live.isEmpty ? nil : live
        if let space = session.spaces.first(where: { $0.id.rawValue == repair.selectedSpaceID }) {
            selectedSpaceID = space.id
        }
    }
}
