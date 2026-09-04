import Foundation

/// Scene-owned browser selection and chrome restoration. It references the
/// authoritative session's Space and tab identities without duplicating any
/// profile or WebKit storage identity, so every native window can restore
/// independently while retaining the existing Space isolation boundary.
struct BrowserWindowState: Codable, Equatable, Identifiable, Sendable {
    let id: BrowserWindowID
    private(set) var selectedSpaceID: SpaceID
    private(set) var selectedTabIDsBySpace: [SpaceID: TabID]
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

    /// Device-local panel preferences. Older records decode the missing key as nil.
    private(set) var extensionSidebarBySpace: [SpaceID: BrowserExtensionSidebarWindowState]?

    /// How far a captured fraction list may sit from summing to one before it
    /// is renormalized on store. Small enough that only rounding survives it.
    private static let fractionSumTolerance = 0.0001

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
        guard let space = session.space(id: spaceID) else { return }
        selectedSpaceID = spaceID
        ensureTabSelection(in: space)
    }

    mutating func selectTab(_ tabID: TabID, in spaceID: SpaceID, session: BrowserSession) {
        guard let space = session.space(id: spaceID), space.contains(tabID) else { return }
        selectedSpaceID = spaceID
        selectedTabIDsBySpace[spaceID] = tabID
    }

    mutating func captureSelection(from session: BrowserSession) {
        selectedSpaceID = session.selectedSpaceID
        selectedTabIDsBySpace = Dictionary(
            uniqueKeysWithValues: session.spaces.compactMap { space in
                guard let tabID = space.selectedTabID else { return nil }
                return (space.id, tabID)
            }
        )
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

    /// Records one split group's column fractions for this window.
    ///
    /// Validation follows `captureSidebar`: a list that cannot describe
    /// columns is ignored rather than repaired into something the caller never
    /// meant. It has to be non-empty, no longer than a group may be, and every
    /// entry has to be a finite share of the container — greater than zero and
    /// no wider than the whole. A list that clears those bars but drifts from
    /// summing to one is normalized on store, so a caller may hand over shares
    /// derived from measured widths without rounding them first.
    mutating func captureSplitLayout(fractions: [Double], for groupID: SplitGroupID) {
        guard !fractions.isEmpty,
            fractions.count <= BrowserSplitGroupPolicy.maximumMembers,
            fractions.allSatisfy({ $0.isFinite && $0 > 0 && $0 <= 1 })
        else { return }
        let total = fractions.reduce(0, +)
        guard total.isFinite, total > 0 else { return }
        let normalized =
            abs(total - 1) <= Self.fractionSumTolerance
            ? fractions
            : fractions.map { $0 / total }
        var fractionsByGroup = splitColumnFractionsByGroup ?? [:]
        fractionsByGroup[groupID] = normalized
        splitColumnFractionsByGroup = fractionsByGroup
    }

    func splitColumnFractions(for groupID: SplitGroupID) -> [Double]? {
        splitColumnFractionsByGroup?[groupID]
    }

    mutating func captureExtensionSidebar(_ preferences: BrowserExtensionSidebarWindowState, for spaceID: SpaceID) {
        var valid = preferences
        if let width = valid.width, !width.isFinite || width <= 0 { valid.width = nil }
        var states = extensionSidebarBySpace ?? [:]
        states[spaceID] = valid
        extensionSidebarBySpace = states
    }

    mutating func repair(using session: BrowserSession) {
        repairSplitLayout(using: session)
        let spaceIDs = Set(session.spaces.map(\.id))
        if let states = extensionSidebarBySpace {
            let live = states.filter { spaceIDs.contains($0.key) }
            extensionSidebarBySpace = live.isEmpty ? nil : live
        }
        selectedTabIDsBySpace = selectedTabIDsBySpace.filter { spaceID, tabID in
            spaceIDs.contains(spaceID) && session.space(id: spaceID)?.contains(tabID) == true
        }
        for space in session.spaces {
            ensureTabSelection(in: space)
        }
        guard !spaceIDs.contains(selectedSpaceID) else { return }
        if spaceIDs.contains(session.selectedSpaceID) {
            selectedSpaceID = session.selectedSpaceID
        } else if let firstSpaceID = session.spaces.first?.id {
            selectedSpaceID = firstSpaceID
        }
    }

    /// Drops column fractions no live group can use.
    ///
    /// An entry survives only while its group still renders as a split in some
    /// Space and still has exactly as many members as the entry has columns. A
    /// group that gained or lost a member is deliberately forgotten rather than
    /// reshaped here: the layout recomputes equal columns, which is a better
    /// answer than stretching stale shares over a different card count. The
    /// whole dictionary returns to `nil` once it empties so an untouched window
    /// stops carrying the key.
    private mutating func repairSplitLayout(using session: BrowserSession) {
        guard let fractionsByGroup = splitColumnFractionsByGroup else { return }
        var memberCountsByGroup: [SplitGroupID: Int] = [:]
        for space in session.spaces {
            for groupID in space.liveSplitGroupIDs {
                memberCountsByGroup[groupID] = space.splitGroupMembers(of: groupID).count
            }
        }
        let live = fractionsByGroup.filter { groupID, fractions in
            memberCountsByGroup[groupID] == fractions.count
        }
        splitColumnFractionsByGroup = live.isEmpty ? nil : live
    }

    private mutating func ensureTabSelection(in space: BrowserSpace) {
        guard selectedTabIDsBySpace[space.id].map(space.contains) != true else { return }
        if let selectedTabID = space.selectedTabID, space.contains(selectedTabID) {
            selectedTabIDsBySpace[space.id] = selectedTabID
        } else if let firstTabID = space.tabs.first?.id {
            selectedTabIDsBySpace[space.id] = firstTabID
        } else {
            selectedTabIDsBySpace[space.id] = nil
        }
    }
}
