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
            return
                customSearchProviders
                .compactMap(\.validatedProvider)
                .first { $0.id == selectedSearchProviderID } ?? .google
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
        BrowserSearchProvider.allCases + customSearchProviders.compactMap(\.validatedProvider)
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

    mutating func upsertCustomSearchProvider(
        _ provider: BrowserCustomSearchProvider
    ) throws {
        guard provider.validatedProvider != nil else {
            throw BrowserCustomSearchProviderError.invalidURL
        }
        let comparableName = provider.name.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )
        guard
            !customSearchProviders.contains(where: {
                $0.id != provider.id
                    && $0.name.folding(
                        options: [.caseInsensitive, .diacriticInsensitive],
                        locale: .current
                    ) == comparableName
            })
        else {
            throw BrowserCustomSearchProviderError.duplicateName
        }
        if let index = customSearchProviders.firstIndex(where: { $0.id == provider.id }) {
            customSearchProviders[index] = provider
        } else {
            guard customSearchProviders.count < 32 else {
                throw BrowserCustomSearchProviderError.tooManyProviders
            }
            customSearchProviders.append(provider)
        }
    }

    mutating func removeCustomSearchProvider(id: UUID) {
        customSearchProviders.removeAll { $0.id == id }
        if selectedSearchProviderID == .custom(id) {
            selectedSearchProviderID = .google
        }
    }

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
        if !availableSearchProviders.contains(where: { $0.id == selectedSearchProviderID }) {
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
        try container.encode(
            customSearchProviders.filter { $0.validatedProvider != nil },
            forKey: .customSearchProviders
        )
        try container.encode(searchSuggestionsEnabled, forKey: .searchSuggestionsEnabled)
        try container.encode(currentTabCleanupPolicy, forKey: .currentTabCleanupPolicy)
        try container.encode(contentBlockingPolicy, forKey: .contentBlockingPolicy)
        try container.encode(dataRetention, forKey: .dataRetention)
    }
}
