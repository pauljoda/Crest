import Foundation

struct BrowserSpaceBrowsingPreferences: Codable, Equatable, Sendable {
    var searchProvider: BrowserSearchProvider
    var currentTabCleanupPolicy: BrowserCurrentTabCleanupPolicy
    var contentBlockingPolicy: BrowserContentBlockingPolicy
    var dataRetention: BrowserSpaceDataRetentionPreferences

    init(
        searchProvider: BrowserSearchProvider,
        currentTabCleanupPolicy: BrowserCurrentTabCleanupPolicy,
        contentBlockingPolicy: BrowserContentBlockingPolicy = .balanced,
        dataRetention: BrowserSpaceDataRetentionPreferences = .default
    ) {
        self.searchProvider = searchProvider
        self.currentTabCleanupPolicy = currentTabCleanupPolicy
        self.contentBlockingPolicy = contentBlockingPolicy
        self.dataRetention = dataRetention
    }

    static let `default` = BrowserSpaceBrowsingPreferences(
        searchProvider: .google,
        currentTabCleanupPolicy: .after12Hours,
        contentBlockingPolicy: .balanced
    )

    private enum CodingKeys: String, CodingKey {
        case searchProvider
        case currentTabCleanupPolicy
        case contentBlockingPolicy
        case dataRetention
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        searchProvider = try container.decode(
            BrowserSearchProvider.self,
            forKey: .searchProvider
        )
        currentTabCleanupPolicy = try container.decode(
            BrowserCurrentTabCleanupPolicy.self,
            forKey: .currentTabCleanupPolicy
        )
        contentBlockingPolicy =
            try container.decodeIfPresent(
                BrowserContentBlockingPolicy.self,
                forKey: .contentBlockingPolicy
            ) ?? .balanced
        dataRetention =
            try container.decodeIfPresent(
                BrowserSpaceDataRetentionPreferences.self,
                forKey: .dataRetention
            ) ?? .default
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(searchProvider, forKey: .searchProvider)
        try container.encode(currentTabCleanupPolicy, forKey: .currentTabCleanupPolicy)
        try container.encode(contentBlockingPolicy, forKey: .contentBlockingPolicy)
        try container.encode(dataRetention, forKey: .dataRetention)
    }
}
