import Foundation

struct PortableFolder: Codable, Equatable, Sendable {
    let id: UUID
    let location: BrowserFolderLocation
    let title: String
    let symbol: String
    let color: BrowserSpaceBrandColor
    var parentID: UUID? = nil
    var isCollapsed = false
    let orderAnchorTabID: UUID?

    init(_ folder: BrowserFolder) {
        id = folder.id.rawValue
        location = folder.location
        title = folder.title
        symbol = folder.symbol
        color = folder.color
        parentID = folder.parentID?.rawValue
        isCollapsed = folder.isCollapsed
        orderAnchorTabID = folder.orderAnchorTabID?.rawValue
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case location
        case title
        case symbol
        case color
        case parentID
        case isCollapsed
        case orderAnchorTabID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        location = try container.decodeIfPresent(BrowserFolderLocation.self, forKey: .location) ?? .saved
        title = try container.decode(String.self, forKey: .title)
        symbol = try container.decode(String.self, forKey: .symbol)
        color =
            try container.decodeIfPresent(
                BrowserSpaceBrandColor.self,
                forKey: .color
            ) ?? .folderDefault
        parentID = try container.decodeIfPresent(UUID.self, forKey: .parentID)
        orderAnchorTabID = try container.decodeIfPresent(UUID.self, forKey: .orderAnchorTabID)
        isCollapsed =
            try container.decodeIfPresent(
                Bool.self,
                forKey: .isCollapsed
            ) ?? false
    }

    func materialize(id: FolderID, parentID: FolderID?) throws -> BrowserFolder {
        try ArchiveValidation.requireText(title, maximumLength: ArchiveLimits.maximumFolderTitleLength)
        try ArchiveValidation.requireText(symbol, maximumLength: ArchiveLimits.maximumSymbolLength)
        return BrowserFolder(
            id: id,
            title: title,
            location: location,
            symbol: symbol,
            color: color,
            parentID: parentID,
            isCollapsed: isCollapsed,
            orderAnchorTabID: orderAnchorTabID.map { TabID(rawValue: $0) }
        )
    }
}
