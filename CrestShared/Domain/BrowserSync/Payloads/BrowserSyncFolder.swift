import Foundation

struct BrowserSyncFolder: Codable, Equatable, Sendable {
    let id: FolderID
    let spaceID: SpaceID
    var title: String
    var symbol: String
    var color: BrowserSpaceBrandColor
    var parentID: FolderID? = nil
    var isCollapsed: Bool
    var collapseModifiedAt: Date?
    var orderToken: String

    init(
        id: FolderID,
        spaceID: SpaceID,
        title: String,
        symbol: String,
        color: BrowserSpaceBrandColor = .folderDefault,
        parentID: FolderID? = nil,
        isCollapsed: Bool = false,
        collapseModifiedAt: Date? = nil,
        orderToken: String
    ) {
        self.id = id
        self.spaceID = spaceID
        self.title = title
        self.symbol = symbol
        self.color = color
        self.parentID = parentID
        self.isCollapsed = isCollapsed
        self.collapseModifiedAt = collapseModifiedAt
        self.orderToken = orderToken
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case spaceID
        case title
        case symbol
        case color
        case parentID
        case isCollapsed
        case collapseModifiedAt
        case orderToken
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(FolderID.self, forKey: .id),
            spaceID: try container.decode(SpaceID.self, forKey: .spaceID),
            title: try container.decode(String.self, forKey: .title),
            symbol: try container.decodeIfPresent(String.self, forKey: .symbol) ?? "folder",
            color: try container.decodeIfPresent(
                BrowserSpaceBrandColor.self,
                forKey: .color
            ) ?? .folderDefault,
            parentID: try container.decodeIfPresent(FolderID.self, forKey: .parentID),
            isCollapsed: try container.decodeIfPresent(
                Bool.self,
                forKey: .isCollapsed
            ) ?? false,
            collapseModifiedAt: try container.decodeIfPresent(
                Date.self,
                forKey: .collapseModifiedAt
            ),
            orderToken: try container.decode(String.self, forKey: .orderToken)
        )
    }
}
