import Foundation

struct BrowserManualSetupPlan: Codable, Equatable, Sendable {
    private static let setupPlacementOrder: [TabPlacement] = [
        .pinned,
        .saved,
        .current,
    ]

    private(set) var spaces: [BrowserManualSetupSpaceDraft]

    init(existing: BrowserSession) {
        spaces = existing.spaces.map {
            BrowserManualSetupSpaceDraft(space: $0, isNew: false)
        }
    }

    mutating func reconcile(with existing: BrowserSession) {
        let currentIDs = Set(existing.spaces.map(\.id))
        spaces.removeAll { !$0.isNew && !currentIDs.contains($0.id) }
        for space in existing.spaces {
            if let index = spaces.firstIndex(where: { $0.id == space.id }) {
                if !spaces[index].isNew {
                    spaces[index].existingPinnedTabCount = space.pinnedTabs.count
                }
            } else {
                spaces.append(BrowserManualSetupSpaceDraft(space: space, isNew: false))
            }
        }
    }

    @discardableResult
    mutating func addSpace() throws -> SpaceID {
        guard spaces.count < BrowserPortableArchive.maximumSpaceCount else {
            throw BrowserManualSetupError.spaceLimitReached
        }
        let number = spaces.count + 1
        let accent = SpaceAccent.allCases[(number - 1) % SpaceAccent.allCases.count]
        let symbol = "square.grid.2x2.fill"
        let space = BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: "Space \(number)",
            symbol: symbol,
            accent: accent,
            branding: .initial(accent: accent, symbol: symbol),
            folders: [],
            tabs: [],
            selectedTabID: nil
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
        let title: String =
            switch intent {
            case .open(let url): Self.title(for: url)
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
        title: String,
        url: URL,
        placement: TabPlacement,
        to spaceID: SpaceID,
        at date: Date = .now
    ) throws -> TabID {
        guard let index = spaces.firstIndex(where: { $0.id == spaceID }) else {
            throw BrowserManualSetupError.missingSpace
        }
        if placement == .pinned,
            spaces[index].existingPinnedTabCount
                + spaces[index].addedTabs.filter({ $0.placement == .pinned }).count
                >= BrowserSpace.maximumPinnedTabs
        {
            throw BrowserManualSetupError.pinnedLimitReached
        }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let tab = BrowserTab(
            title: trimmedTitle.isEmpty ? Self.title(for: url) : trimmedTitle,
            url: url,
            symbol: placement == .pinned ? "pin.fill" : "globe",
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
        if placement == .pinned,
            spaces[spaceIndex].existingPinnedTabCount
                + spaces[spaceIndex].addedTabs.filter({
                    $0.placement == .pinned && $0.id != tabID
                }).count >= BrowserSpace.maximumPinnedTabs
        {
            throw BrowserManualSetupError.pinnedLimitReached
        }
        spaces[spaceIndex].addedTabs[tabIndex].placement = placement
        spaces[spaceIndex].addedTabs[tabIndex].savedURL =
            placement == .current
            ? nil
            : spaces[spaceIndex].addedTabs[tabIndex].url
        spaces[spaceIndex].addedTabs[tabIndex].symbol =
            placement == .pinned
            ? "pin.fill"
            : "globe"
    }

    func preview(mergingInto existing: BrowserSession) throws -> BrowserSession {
        let newSpaces = spaces.filter(\.isNew)
        guard
            existing.spaces.count + newSpaces.count
                <= BrowserPortableArchive.maximumSpaceCount
        else {
            throw BrowserManualSetupError.spaceLimitReached
        }

        var result = existing
        var firstAffectedSpaceID: SpaceID?
        for draft in spaces {
            if draft.isNew {
                var created = BrowserSpace(
                    id: draft.id,
                    profile: draft.profile,
                    // A new Space earns the same blank-field handling an edited one
                    // gets; `apply(to:)` cannot run before the Space exists.
                    name: draft.customization.resolvedName,
                    symbol: draft.customization.resolvedSymbol,
                    accent: draft.customization.accent,
                    branding: draft.customization.branding.normalized(),
                    folders: [],
                    tabs: ordered(draft.addedTabs),
                    selectedTabID: selectedTabID(in: draft.addedTabs)
                )
                if created.tabs.isEmpty {
                    let startPage = BrowserTab.startPage()
                    created.tabs = [startPage]
                    created.selectedTabID = startPage.id
                }
                result.spaces.append(created)
                firstAffectedSpaceID = firstAffectedSpaceID ?? created.id
                continue
            }

            guard
                let destinationIndex = result.spaces.firstIndex(where: {
                    $0.id == draft.id
                })
            else { continue }
            var destination = result.spaces[destinationIndex]
            draft.customization.apply(to: &destination)
            try append(draft.addedTabs, to: &destination)
            result.spaces[destinationIndex] = destination
            if !draft.addedTabs.isEmpty {
                firstAffectedSpaceID = firstAffectedSpaceID ?? destination.id
            }
        }
        if let firstAffectedSpaceID {
            result.selectedSpaceID = firstAffectedSpaceID
        }
        result.disposableSeedMarker = nil
        result.repairRuntimeIntegrity()
        return result
    }

    private func append(_ tabs: [BrowserTab], to space: inout BrowserSpace) throws {
        let pinnedTotal = space.pinnedTabs.count + tabs.filter { $0.placement == .pinned }.count
        guard pinnedTotal <= BrowserSpace.maximumPinnedTabs else {
            throw BrowserManualSetupError.pinnedLimitReached
        }
        let additions = ordered(tabs)
        let existingCurrentIndex =
            space.tabs.firstIndex { $0.placement == .current }
            ?? space.tabs.endIndex
        let pinned = additions.filter { $0.placement == .pinned }
        space.tabs.insert(
            contentsOf: pinned,
            at: space.tabs.firstIndex {
                $0.placement != .pinned
            } ?? space.tabs.endIndex)
        let saved = additions.filter { $0.placement == .saved }
        space.tabs.insert(contentsOf: saved, at: existingCurrentIndex + pinned.count)
        let current = additions.filter { $0.placement == .current }
        space.tabs.append(contentsOf: current)
        if let selected = selectedTabID(in: additions) {
            space.selectedTabID = selected
        }
    }

    private func ordered(_ tabs: [BrowserTab]) -> [BrowserTab] {
        Self.setupPlacementOrder.flatMap { placement in
            tabs.filter { $0.placement == placement }
        }
    }

    private func selectedTabID(in tabs: [BrowserTab]) -> TabID? {
        tabs.last(where: { $0.placement == .current })?.id
            ?? tabs.first?.id
    }

    private static func title(for url: URL) -> String {
        let host = url.host(percentEncoded: false) ?? url.absoluteString
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
