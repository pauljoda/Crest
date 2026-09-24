import Foundation

extension SearchProvider: Identifiable {
    // MARK: - Variables

    var id: String {
        name
    }

    /// Whether this is a Space's own engine rather than a built-in.
    var isCustom: Bool {
        Self.named(name) == nil
    }

    /// This engine as a Space's selection names it to the core: a built-in,
    /// or a custom engine's identity.
    var selection: (builtIn: BuiltInSearchEngine?, customEngineID: UUID?) {
        if let builtIn = BuiltInSearchEngine.named(name) { return (builtIn, nil) }
        return (nil, UUID(uuidString: String(name.dropFirst(Self.customPrefix.count))))
    }

    /// The website a custom engine's favicon is loaded from.
    var iconPageURL: URL? {
        guard isCustom else { return nil }
        guard
            let components = URLComponents(
                string:
                    searchTemplate
                    .replacingOccurrences(of: "{searchTerms}", with: "crest")
                    .replacingOccurrences(of: "%s", with: "crest")
            )
        else { return nil }
        var origin = URLComponents()
        origin.scheme = components.scheme
        origin.host = components.host
        origin.port = components.port
        origin.path = "/"
        return origin.url
    }

    // MARK: - Initializers

    /// A Space's custom engine, named as the core names one: the core's
    /// custom prefix and the engine's identity in the core's spelling.
    init(custom: BrowserCustomSearchProvider) {
        self.init(
            name: Self.customPrefix + custom.id.coreIdentifier, title: custom.name, logo: nil,
            searchTemplate: custom.searchURLTemplate, suggestionTemplate: custom.suggestionURLTemplate)
    }

    // MARK: - Actions - Queries

    func searchURL(for query: String) -> URL? {
        BrowserCorePolicy.searchURL(provider: self, query: query, purpose: .search)
    }

    func suggestionURL(for query: String) -> URL? {
        BrowserCorePolicy.searchURL(provider: self, query: query, purpose: .suggestions)
    }
}
