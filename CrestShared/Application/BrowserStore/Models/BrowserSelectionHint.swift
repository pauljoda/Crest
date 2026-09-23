import Foundation

/// The follow-up selection the core suggests after a command: the Space the
/// requesting window may switch to, and the tab it may show in each Space whose
/// shown tab the command changed (nil to show none). The core stores no
/// selection; a window applies the hint to its own `BrowserStoreSelection`.
struct BrowserSelectionHint: Decodable, Equatable, Sendable {
    // MARK: - Types

    struct TabChoice: Decodable, Equatable, Sendable {
        let spaceID: SpaceID
        let tabID: TabID?

        private enum CodingKeys: String, CodingKey {
            case spaceID = "spaceId"
            case tabID = "tabId"
        }

        init(spaceID: SpaceID, tabID: TabID?) {
            self.spaceID = spaceID
            self.tabID = tabID
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            spaceID = SpaceID(rawValue: try values.decode(UUID.self, forKey: .spaceID))
            tabID = try values.decodeIfPresent(UUID.self, forKey: .tabID).map(TabID.init(rawValue:))
        }
    }

    // MARK: - Variables

    static let none = BrowserSelectionHint(spaceID: nil, tabs: [])

    let spaceID: SpaceID?
    let tabs: [TabChoice]

    var isEmpty: Bool { spaceID == nil && tabs.isEmpty }

    // MARK: - Initializers

    init(spaceID: SpaceID?, tabs: [TabChoice]) {
        self.spaceID = spaceID
        self.tabs = tabs
    }

    private enum CodingKeys: String, CodingKey {
        case spaceID = "spaceId"
        case tabs
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        spaceID = try values.decodeIfPresent(UUID.self, forKey: .spaceID).map(SpaceID.init(rawValue:))
        tabs = try values.decodeIfPresent([TabChoice].self, forKey: .tabs) ?? []
    }
}
