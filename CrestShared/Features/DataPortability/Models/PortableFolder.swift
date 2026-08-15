import Foundation

struct PortableFolder: Codable, Equatable, Sendable {
    let id: UUID
    let title: String
    let symbol: String
    let color: BrowserSpaceBrandColor
    var parentID: UUID? = nil
    var isCollapsed = false

    init(_ folder: SavedFolder) {
        id = folder.id.rawValue
        title = folder.title
        symbol = folder.symbol
        color = folder.color
        parentID = folder.parentID?.rawValue
        isCollapsed = folder.isCollapsed
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case symbol
        case color
        case parentID
        case isCollapsed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        symbol = try container.decode(String.self, forKey: .symbol)
        color =
            try container.decodeIfPresent(
                BrowserSpaceBrandColor.self,
                forKey: .color
            ) ?? .folderDefault
        parentID = try container.decodeIfPresent(UUID.self, forKey: .parentID)
        isCollapsed =
            try container.decodeIfPresent(
                Bool.self,
                forKey: .isCollapsed
            ) ?? false
    }

    func materialize(id: FolderID, parentID: FolderID?) throws -> SavedFolder {
        try ArchiveValidation.requireText(title, maximumLength: ArchiveLimits.maximumFolderTitleLength)
        try ArchiveValidation.requireText(symbol, maximumLength: ArchiveLimits.maximumSymbolLength)
        return SavedFolder(
            id: id,
            title: title,
            symbol: symbol,
            color: color,
            parentID: parentID,
            isCollapsed: isCollapsed
        )
    }
}
