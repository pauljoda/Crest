import Foundation

struct BrowserManualSetupPlan: Codable, Equatable, Sendable {
    private static let setupPlacementOrder: [TabPlacement] = [
        .pinned,
        .saved,
        .current,
    ]

    private(set) var spaces: [BrowserManualSetupSpaceDraft]
    // Optional so previously saved setup drafts continue to decode. An untouched
    // draft does not replace an order changed elsewhere while setup was open.
    private var spaceOrderWasEdited: Bool?

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

    var coreSpaceOrderWasEdited: Bool { spaceOrderWasEdited == true }

    func preview(mergingInto existing: BrowserSession) throws -> BrowserSession {
        return try BrowserCoreWorkspaceImport.preview(BrowserCoreWorkspaceImport.manual(self), existing: existing)
    }

    private static func title(for url: URL) -> String {
        let host = url.host(percentEncoded: false) ?? url.absoluteString
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
