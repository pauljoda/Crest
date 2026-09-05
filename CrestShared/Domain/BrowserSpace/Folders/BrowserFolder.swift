import Foundation

struct BrowserFolder: Codable, Equatable, Identifiable, Sendable {
    let id: FolderID
    var location: BrowserFolderLocation
    var title: String
    var symbol: String
    var color: BrowserSpaceBrandColor
    var parentID: FolderID?
    var isCollapsed: Bool
    var collapseModifiedAt: Date?
    /// The next tab in the parent section when this subtree is empty.
    var orderAnchorTabID: TabID?

    init(
        id: FolderID = FolderID(),
        title: String,
        location: BrowserFolderLocation = .saved,
        symbol: String = "folder",
        color: BrowserSpaceBrandColor = .folderDefault,
        parentID: FolderID? = nil,
        isCollapsed: Bool = false,
        collapseModifiedAt: Date? = nil,
        orderAnchorTabID: TabID? = nil
    ) {
        self.id = id
        self.location = location
        self.title = title
        self.symbol = symbol
        self.color = color
        self.parentID = parentID
        self.isCollapsed = isCollapsed
        self.collapseModifiedAt = collapseModifiedAt
        self.orderAnchorTabID = orderAnchorTabID
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case location
        case title
        case symbol
        case color
        case parentID
        case isCollapsed
        case collapseModifiedAt
        case orderAnchorTabID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(FolderID.self, forKey: .id),
            title: try container.decode(String.self, forKey: .title),
            location: try container.decodeIfPresent(BrowserFolderLocation.self, forKey: .location) ?? .saved,
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
            orderAnchorTabID: try container.decodeIfPresent(TabID.self, forKey: .orderAnchorTabID)
        )
    }
}
