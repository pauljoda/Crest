import Foundation

struct SavedFolder: Codable, Equatable, Identifiable, Sendable {
    let id: FolderID
    var title: String
    var symbol: String
    var color: BrowserSpaceBrandColor
    var parentID: FolderID?
    var isCollapsed: Bool
    var collapseModifiedAt: Date?

    init(
        id: FolderID = FolderID(),
        title: String,
        symbol: String = "folder",
        color: BrowserSpaceBrandColor = .folderDefault,
        parentID: FolderID? = nil,
        isCollapsed: Bool = false,
        collapseModifiedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.color = color
        self.parentID = parentID
        self.isCollapsed = isCollapsed
        self.collapseModifiedAt = collapseModifiedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case symbol
        case color
        case parentID
        case isCollapsed
        case collapseModifiedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(FolderID.self, forKey: .id),
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
            )
        )
    }
}
