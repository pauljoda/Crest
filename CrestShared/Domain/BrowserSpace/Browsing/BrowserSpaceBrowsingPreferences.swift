import Foundation

struct BrowserSpaceBrowsingPreferences: Codable, Equatable, Sendable {
    /// The selected engine's name, as Spaces store and sync it.
    private var selectedSearchProviderID: String
    private(set) var customSearchProviders: [BrowserCustomSearchProvider]
    var searchSuggestionsEnabled: Bool
    var currentTabCleanupPolicy: CurrentTabCleanup
    var contentBlockingPolicy: ContentBlockingPolicy
    var dataRetention: BrowserSpaceDataRetentionPreferences

    var searchProvider: SearchProvider {
        get {
            availableSearchProviders.first { $0.name == selectedSearchProviderID } ?? .google
        }
        set {
            guard availableSearchProviders.contains(newValue) else {
                selectedSearchProviderID = SearchProvider.google.name
                return
            }
            selectedSearchProviderID = newValue.name
        }
    }

    var availableSearchProviders: [SearchProvider] {
        SearchProvider.all + customSearchProviders.map(\.provider)
    }

    init(
        searchProvider: SearchProvider,
        currentTabCleanupPolicy: CurrentTabCleanup,
        contentBlockingPolicy: ContentBlockingPolicy = .balanced,
        dataRetention: BrowserSpaceDataRetentionPreferences = .default,
        customSearchProviders: [BrowserCustomSearchProvider] = [],
        searchSuggestionsEnabled: Bool = false
    ) {
        selectedSearchProviderID = searchProvider.name
        self.customSearchProviders = customSearchProviders
        self.searchSuggestionsEnabled = searchSuggestionsEnabled
        self.currentTabCleanupPolicy = currentTabCleanupPolicy
        self.contentBlockingPolicy = contentBlockingPolicy
        self.dataRetention = dataRetention
        if !availableSearchProviders.contains(where: { $0.name == selectedSearchProviderID }) {
            selectedSearchProviderID = SearchProvider.google.name
        }
    }

    /// TRANSITIONAL until S6.7 retires the Swift session copy: the preferences
    /// the core publishes, read the way the decoder reads its stored form.
    init(core preferences: BrowsingPreferences) {
        selectedSearchProviderID = preferences.selectedSearchProviderID
        customSearchProviders = preferences.customSearchProviders.map {
            BrowserCustomSearchProvider(
                id: $0.id, name: $0.name, searchURLTemplate: $0.searchURLTemplate,
                suggestionURLTemplate: $0.suggestionURLTemplate)
        }
        searchSuggestionsEnabled = preferences.searchSuggestionsEnabled
        currentTabCleanupPolicy = preferences.currentTabCleanup
        contentBlockingPolicy = preferences.contentBlocking
        dataRetention = BrowserSpaceDataRetentionPreferences(
            history: preferences.dataRetention.history, archive: preferences.dataRetention.archive,
            downloads: preferences.dataRetention.downloads)
        restoreSelection()
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
        let legacyID =
            try container.decodeIfPresent(String.self, forKey: .searchProvider) ?? SearchProvider.google.name
        selectedSearchProviderID =
            (try? container.decodeIfPresent(String.self, forKey: .selectedSearchProviderID)) ?? legacyID
        customSearchProviders =
            (try? container.decodeIfPresent(
                [BrowserCustomSearchProvider].self,
                forKey: .customSearchProviders
            )) ?? []
        searchSuggestionsEnabled =
            (try? container.decodeIfPresent(Bool.self, forKey: .searchSuggestionsEnabled))
            ?? false
        currentTabCleanupPolicy = try container.decode(
            CurrentTabCleanup.self,
            forKey: .currentTabCleanupPolicy
        )
        contentBlockingPolicy =
            try container.decodeIfPresent(
                ContentBlockingPolicy.self,
                forKey: .contentBlockingPolicy
            ) ?? .balanced
        dataRetention =
            try container.decodeIfPresent(
                BrowserSpaceDataRetentionPreferences.self,
                forKey: .dataRetention
            ) ?? .default
        restoreSelection()
    }

    /// Stored engines that no longer validate, including ones synced from
    /// elsewhere, are dropped by the core's restore rule and never offered.
    private mutating func restoreSelection() {
        if !customSearchProviders.isEmpty,
            let restored = BrowserCorePolicy.restoredCustomSearchProviders(
                customSearchProviders, selectedID: selectedSearchProviderID)
        {
            customSearchProviders = restored.providers
            selectedSearchProviderID = restored.selectedID
        } else if !availableSearchProviders.contains(where: { $0.name == selectedSearchProviderID }) {
            selectedSearchProviderID = SearchProvider.google.name
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // The legacy key names a built-in only.
        let legacyFallback = SearchProvider.named(selectedSearchProviderID)?.name ?? SearchProvider.google.name
        try container.encode(legacyFallback, forKey: .searchProvider)
        try container.encode(selectedSearchProviderID, forKey: .selectedSearchProviderID)
        try container.encode(customSearchProviders, forKey: .customSearchProviders)
        try container.encode(searchSuggestionsEnabled, forKey: .searchSuggestionsEnabled)
        try container.encode(currentTabCleanupPolicy, forKey: .currentTabCleanupPolicy)
        try container.encode(contentBlockingPolicy, forKey: .contentBlockingPolicy)
        try container.encode(dataRetention, forKey: .dataRetention)
    }
}
