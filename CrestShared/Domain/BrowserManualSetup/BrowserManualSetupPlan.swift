import Foundation

/// The native draft of a manual setup. The core admits each edit (Space and
/// pinned limits, new-Space identity, tab presentation) and reconciles the
/// draft with Spaces changed elsewhere; the workspace import applies it.
struct BrowserManualSetupPlan: Codable, Equatable, Sendable {
    private(set) var spaces: [BrowserManualSetupSpaceDraft]
    // Optional so previously saved setup drafts continue to decode. An untouched
    // draft does not replace an order changed elsewhere while setup was open.
    private var spaceOrderWasEdited: Bool?

    init(existing: BrowserSession) {
        spaces = existing.spaces.map {
            BrowserManualSetupSpaceDraft(space: $0, isNew: false)
        }
    }

    /// Follows Spaces changed elsewhere while setup was open. When the core
    /// cannot answer, the draft is left as it was.
    mutating func reconcile(with existing: BrowserSession) {
        guard let entries = BrowserCorePolicy.reconcileSetup(
            drafts: spaces.map { ($0.id, $0.isNew) }, existing: existing.spaces.map(\.id))
        else { return }
        spaces = entries.map { entry in
            guard let draftIndex = entry.draft else {
                return BrowserManualSetupSpaceDraft(space: existing.spaces[entry.existing!], isNew: false)
            }
            var draft = spaces[draftIndex]
            if let existingIndex = entry.existing {
                draft.existingPinnedTabCount = existing.spaces[existingIndex].pinnedTabs.count
            }
            return draft
        }
    }

    @discardableResult
    mutating func addSpace() throws -> SpaceID {
        let admitted = try BrowserCorePolicy.setupSpace(draftCount: spaces.count)
        let space = BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: admitted.name,
            symbol: admitted.symbol,
            accent: admitted.accent,
            branding: .initial(accent: admitted.accent, symbol: admitted.symbol),
            folders: [],
            tabs: []
        )
        spaces.append(BrowserManualSetupSpaceDraft(space: space, isNew: true))
        return space.id
    }

    @discardableResult
    mutating func removeSpace(_ spaceID: SpaceID) -> Bool {
        guard let index = spaces.firstIndex(where: { $0.id == spaceID && $0.isNew }) else {
            return false
        }
        spaces.remove(at: index)
        return true
    }

    mutating func moveSpace(_ spaceID: SpaceID, to targetID: SpaceID) {
        guard let source = spaces.firstIndex(where: { $0.id == spaceID }),
            let target = spaces.firstIndex(where: { $0.id == targetID }), source != target
        else { return }
        let moved = spaces.remove(at: source)
        spaces.insert(moved, at: target)
        spaceOrderWasEdited = true
    }

    mutating func setSpaceIdentity(
        name: String,
        symbol: String,
        for spaceID: SpaceID
    ) {
        guard let index = spaces.firstIndex(where: { $0.id == spaceID }) else { return }
        spaces[index].customization.name = name
        spaces[index].customization.symbol = symbol
    }

    mutating func setSpaceBranding(
        _ branding: BrowserSpaceBranding,
        for spaceID: SpaceID
    ) {
        guard let index = spaces.firstIndex(where: { $0.id == spaceID }) else { return }
        spaces[index].customization.branding = branding.normalized()
    }

    mutating func discardAddedTabs() {
        for index in spaces.indices {
            spaces[index].addedTabs.removeAll()
        }
    }

    @discardableResult
    mutating func addTab(
        input: String,
        placement: TabPlacement,
        to spaceID: SpaceID,
        at date: Date = .now
    ) throws -> TabID {
        guard let intent = AddressResolver.intent(input) else {
            throw BrowserManualSetupError.invalidAddress
        }
        let title: String? =
            switch intent {
            case .open: nil
            case .search(let query, _, _): query
            }
        return try addTab(
            title: title,
            url: intent.url,
            placement: placement,
            to: spaceID,
            at: date
        )
    }

    @discardableResult
    mutating func addTab(
        title: String?,
        url: URL,
        placement: TabPlacement,
        to spaceID: SpaceID,
        at date: Date = .now
    ) throws -> TabID {
        guard let index = spaces.firstIndex(where: { $0.id == spaceID }) else {
            throw BrowserManualSetupError.missingSpace
        }
        let admitted = try BrowserCorePolicy.setupTab(
            placement: placement,
            existingPinnedCount: spaces[index].existingPinnedTabCount,
            addedPinnedCount: spaces[index].addedTabs.filter({ $0.placement == .pinned }).count,
            url: url,
            title: title
        )
        let tab = BrowserTab(
            title: admitted.title,
            url: url,
            symbol: admitted.symbol,
            placement: placement,
            lastActivatedAt: date
        )
        spaces[index].addedTabs.append(tab)
        return tab.id
    }

    @discardableResult
    mutating func removeTab(_ tabID: TabID, from spaceID: SpaceID) -> Bool {
        guard let spaceIndex = spaces.firstIndex(where: { $0.id == spaceID }),
            let tabIndex = spaces[spaceIndex].addedTabs.firstIndex(where: {
                $0.id == tabID
            })
        else { return false }
        spaces[spaceIndex].addedTabs.remove(at: tabIndex)
        return true
    }

    mutating func setPlacement(
        _ placement: TabPlacement,
        for tabID: TabID,
        in spaceID: SpaceID
    ) throws {
        guard let spaceIndex = spaces.firstIndex(where: { $0.id == spaceID }),
            let tabIndex = spaces[spaceIndex].addedTabs.firstIndex(where: {
                $0.id == tabID
            })
        else {
            throw BrowserManualSetupError.missingSpace
        }
        let tab = spaces[spaceIndex].addedTabs[tabIndex]
        guard let url = tab.url else { throw BrowserManualSetupError.invalidAddress }
        let admitted = try BrowserCorePolicy.setupTab(
            placement: placement,
            existingPinnedCount: spaces[spaceIndex].existingPinnedTabCount,
            addedPinnedCount: spaces[spaceIndex].addedTabs.filter({
                $0.placement == .pinned && $0.id != tabID
            }).count,
            url: url,
            title: tab.title
        )
        spaces[spaceIndex].addedTabs[tabIndex].placement = placement
        spaces[spaceIndex].addedTabs[tabIndex].savedURL = admitted.keepsSavedURL ? url : nil
        spaces[spaceIndex].addedTabs[tabIndex].symbol = admitted.symbol
    }

    /// The session the setup would leave `browser`'s workspace with. Throws
    /// the rule that would refuse it.
    @MainActor
    func preview(in browser: BrowserStore) throws -> BrowserSession {
        try browser.importPreview(try intent(in: browser), of: sources)
    }

    /// The setup's drafts as Spaces: each with its identity, profile, name
    /// and look, holding the tabs it adds.
    var sources: [BrowserSpace] {
        spaces.map { draft in
            BrowserSpace(
                id: draft.id, profile: draft.profile, name: draft.customization.name,
                symbol: draft.customization.symbol, accent: draft.customization.accent,
                branding: draft.customization.branding, folders: [], tabs: draft.addedTabs)
        }
    }

    /// The setup these drafts make, issued from `browser`'s window.
    @MainActor
    func intent(in browser: BrowserStore) throws -> ApplyManualSetup {
        ApplyManualSetup(
            workspaceID: browser.family.workspaceID, windowID: browser.windowID.rawValue,
            spaces: try BrowserSpace.storedFormat(sources),
            drafts: spaces.map {
                SetupSpace(spaceID: $0.id.rawValue, isNew: $0.isNew, customization: $0.customization.core)
            },
            orderWasEdited: spaceOrderWasEdited == true)
    }
}
