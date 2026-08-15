import Foundation

struct BrowserSyncTab: Codable, Equatable, Sendable {
    let id: TabID
    let spaceID: SpaceID
    var title: String
    var url: URL?
    var savedURL: URL?
    var symbol: String
    var placement: TabPlacement
    var folderID: FolderID?
    var splitGroupID: SplitGroupID? = nil
    var orderToken: String
    var lastActivatedAt: Date
    var positionModifiedAt: Date? = nil
    var customTitle: String? = nil
    var titleModifiedAt: Date? = nil
    var keepsPageLoaded: Bool = false

    init(
        id: TabID,
        spaceID: SpaceID,
        title: String,
        url: URL?,
        savedURL: URL? = nil,
        symbol: String,
        placement: TabPlacement,
        folderID: FolderID? = nil,
        splitGroupID: SplitGroupID? = nil,
        orderToken: String,
        lastActivatedAt: Date,
        positionModifiedAt: Date? = nil,
        customTitle: String? = nil,
        titleModifiedAt: Date? = nil,
        keepsPageLoaded: Bool = false
    ) {
        self.id = id
        self.spaceID = spaceID
        self.title = title
        self.url = url
        self.savedURL = savedURL
        self.symbol = symbol
        self.placement = placement
        self.folderID = folderID
        self.splitGroupID = splitGroupID
        self.orderToken = orderToken
        self.lastActivatedAt = lastActivatedAt
        self.positionModifiedAt = positionModifiedAt
        self.customTitle = customTitle
        self.titleModifiedAt = titleModifiedAt
        self.keepsPageLoaded = keepsPageLoaded
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case spaceID
        case title
        case url
        case savedURL
        case symbol
        case placement
        case folderID
        case splitGroupID
        case orderToken
        case lastActivatedAt
        case positionModifiedAt
        case customTitle
        case titleModifiedAt
        case keepsPageLoaded
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(TabID.self, forKey: .id)
        spaceID = try container.decode(SpaceID.self, forKey: .spaceID)
        title = try container.decode(String.self, forKey: .title)
        url = try container.decodeIfPresent(URL.self, forKey: .url)
        savedURL = try container.decodeIfPresent(URL.self, forKey: .savedURL)
        symbol = try container.decode(String.self, forKey: .symbol)
        placement = try container.decode(TabPlacement.self, forKey: .placement)
        folderID = try container.decodeIfPresent(FolderID.self, forKey: .folderID)
        splitGroupID = try container.decodeIfPresent(
            SplitGroupID.self,
            forKey: .splitGroupID
        )
        orderToken = try container.decode(String.self, forKey: .orderToken)
        lastActivatedAt = try container.decode(Date.self, forKey: .lastActivatedAt)
        positionModifiedAt = try container.decodeIfPresent(
            Date.self,
            forKey: .positionModifiedAt
        )
        customTitle = try container.decodeIfPresent(String.self, forKey: .customTitle)
        titleModifiedAt = try container.decodeIfPresent(
            Date.self,
            forKey: .titleModifiedAt
        )
        keepsPageLoaded =
            try container.decodeIfPresent(
                Bool.self,
                forKey: .keepsPageLoaded
            ) ?? false
    }
}
