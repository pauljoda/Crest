import Foundation

struct BrowserSpaceBrowsingPreferences: Codable, Equatable, Sendable {
    private var selectedSearchProviderID: BrowserSearchProviderID
    private(set) var customSearchProviders: [BrowserCustomSearchProvider]
    var searchSuggestionsEnabled: Bool
    var currentTabCleanupPolicy: BrowserCurrentTabCleanupPolicy
    var contentBlockingPolicy: BrowserContentBlockingPolicy
    var dataRetention: BrowserSpaceDataRetentionPreferences

    var searchProvider: BrowserSearchProvider {
        get {
            if let builtIn = BrowserSearchProvider.provider(with: selectedSearchProviderID) {
                return builtIn
            }
            return customSearchProviders.first { .custom($0.id) == selectedSearchProviderID }?.provider ?? .google
        }
        set {
            guard availableSearchProviders.contains(where: { $0.id == newValue.id }) else {
                selectedSearchProviderID = .google
                return
            }
            selectedSearchProviderID = newValue.id
        }
    }

    var availableSearchProviders: [BrowserSearchProvider] {
        BrowserSearchProvider.allCases + customSearchProviders.map(\.provider)
    }

    init(
        searchProvider: BrowserSearchProvider,
        currentTabCleanupPolicy: BrowserCurrentTabCleanupPolicy,
        contentBlockingPolicy: BrowserContentBlockingPolicy = .balanced,
        dataRetention: BrowserSpaceDataRetentionPreferences = .default,
        customSearchProviders: [BrowserCustomSearchProvider] = [],
        searchSuggestionsEnabled: Bool = false
    ) {
        selectedSearchProviderID = searchProvider.id
        self.customSearchProviders = customSearchProviders
        self.searchSuggestionsEnabled = searchSuggestionsEnabled
        self.currentTabCleanupPolicy = currentTabCleanupPolicy
        self.contentBlockingPolicy = contentBlockingPolicy
        self.dataRetention = dataRetention
        if !availableSearchProviders.contains(where: { $0.id == selectedSearchProviderID }) {
            selectedSearchProviderID = .google
        }
    }

    static let `default` = BrowserSpaceBrowsingPreferences(
        searchProvider: .google,
        currentTabCleanupPolicy: .after12Hours,
        contentBlockingPolicy: .balanced
    )

    private enum CodingKeys: String, CodingKey {
        case searchProvider
        case selectedSearchProviderID
        case customSearchProviders
        case searchSuggestionsEnabled
        case currentTabCleanupPolicy
        case contentBlockingPolicy
        case dataRetention
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyRaw =
            try container.decodeIfPresent(String.self, forKey: .searchProvider)
            ?? BrowserSearchProviderID.google.rawValue
        let legacyID = BrowserSearchProviderID(rawValue: legacyRaw) ?? .google
        selectedSearchProviderID =
            (try? container.decodeIfPresent(
                BrowserSearchProviderID.self,
                forKey: .selectedSearchProviderID
            )) ?? legacyID
        customSearchProviders =
            (try? container.decodeIfPresent(
                [BrowserCustomSearchProvider].self,
                forKey: .customSearchProviders
            )) ?? []
        searchSuggestionsEnabled =
            (try? container.decodeIfPresent(Bool.self, forKey: .searchSuggestionsEnabled))
            ?? false
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
        // Stored engines that no longer validate, including ones synced from
        // elsewhere, are dropped by the core's restore rule and never offered.
        if !customSearchProviders.isEmpty,
            let restored = BrowserCorePolicy.restoredCustomSearchProviders(
                customSearchProviders, selectedID: selectedSearchProviderID)
        {
            customSearchProviders = restored.providers
            selectedSearchProviderID = restored.selectedID
        } else if !availableSearchProviders.contains(where: { $0.id == selectedSearchProviderID }) {
            selectedSearchProviderID = .google
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let legacyFallback =
            selectedSearchProviderID.isCustom
            ? BrowserSearchProviderID.google.rawValue
            : selectedSearchProviderID.rawValue
        try container.encode(legacyFallback, forKey: .searchProvider)
        try container.encode(selectedSearchProviderID, forKey: .selectedSearchProviderID)
        try container.encode(customSearchProviders, forKey: .customSearchProviders)
        try container.encode(searchSuggestionsEnabled, forKey: .searchSuggestionsEnabled)
        try container.encode(currentTabCleanupPolicy, forKey: .currentTabCleanupPolicy)
        try container.encode(contentBlockingPolicy, forKey: .contentBlockingPolicy)
        try container.encode(dataRetention, forKey: .dataRetention)
    }
}
