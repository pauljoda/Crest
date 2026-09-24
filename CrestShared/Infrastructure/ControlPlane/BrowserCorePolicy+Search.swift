import Foundation

enum BrowserSearchQueryPurpose: String, Encodable {
    case search
    case suggestions
}

/// A custom search engine as the core stores and validates it.
struct BrowserCoreSearchProviderRecord: Codable, Sendable {
    // MARK: - Variables

    let id: String
    let name: String
    let searchURLTemplate: String
    @BrowserCoreNullable var suggestionURLTemplate: String?

    /// The engine this record describes, or nil when its identity is not one.
    var provider: BrowserCustomSearchProvider? {
        guard let id = UUID(uuidString: id) else { return nil }
        return BrowserCustomSearchProvider(
            id: id, name: name, searchURLTemplate: searchURLTemplate, suggestionURLTemplate: suggestionURLTemplate)
    }

    // MARK: - Initializers

    init(_ provider: BrowserCustomSearchProvider) {
        id = provider.id.coreIdentifier
        name = provider.name
        searchURLTemplate = provider.searchURLTemplate
        suggestionURLTemplate = provider.suggestionURLTemplate
    }
}

extension BrowserCoreSearchProviderRecord {
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case searchURLTemplate
        case suggestionURLTemplate
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        searchURLTemplate = try container.decode(String.self, forKey: .searchURLTemplate)
        suggestionURLTemplate = try container.decode(
            BrowserCoreOptional<String>.self, forKey: .suggestionURLTemplate
        ).wrappedValue
    }
}

extension BrowserCorePolicy {
    /// How the core names a search engine: a built-in identity, or a custom
    /// engine with its stored templates, which the core validates before use.
    struct SearchProviderDescriptor: Encodable, Sendable {
        private enum CodingKeys: String, CodingKey {
            case id
            case name
            case searchURLTemplate
            case suggestionURLTemplate
        }

        let provider: BrowserSearchProvider

        init(_ provider: BrowserSearchProvider) {
            self.provider = provider
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(provider.id, forKey: .id)
            guard provider.builtIn == nil else { return }
            try container.encode(provider.title, forKey: .name)
            try container.encode(provider.customSearchURLTemplate ?? "", forKey: .searchURLTemplate)
            try container.encode(provider.customSuggestionURLTemplate, forKey: .suggestionURLTemplate)
        }
    }
}

/// Search and translation decisions owned by the portable core.
extension BrowserCorePolicy {
    // MARK: - Types

    private struct SearchURLRequest: Encodable {
        let searchProvider: SearchProviderDescriptor
        let query: String
        let purpose: BrowserSearchQueryPurpose
    }

    private struct SearchURLAnswer: Decodable {
        let url: String
    }

    private struct CustomProvidersRequest: Encodable {
        let selectedID: BrowserSearchProviderID
        let providers: [BrowserCoreSearchProviderRecord]
    }

    private struct CustomProvidersAnswer: Decodable {
        let indices: [Int]
        let selectedID: BrowserSearchProviderID
    }

    private struct TranslationRuleRequest: Encodable {
        let rules: BrowserAutomaticTranslationRules
        let sourceID: String
    }

    private struct TranslationRuleAnswer: Decodable {
        @BrowserCoreOptional var rule: BrowserAutomaticTranslationRules.Rule?
        @BrowserCoreOptional var target: String?
    }

    private struct LanguageMatchesRequest: Encodable {
        let language: String
        let candidates: [String]
    }

    private struct LanguageMatchesAnswer: Decodable {
        let matches: [Bool]
    }

    // MARK: - Actions - Search

    /// The results or suggestion URL for a query. Nil when the engine has no
    /// suggestion endpoint or the core cannot answer.
    static func searchURL(
        provider: BrowserSearchProvider, query: String,
        purpose: BrowserSearchQueryPurpose
    ) -> URL? {
        let request = SearchURLRequest(
            searchProvider: SearchProviderDescriptor(provider), query: query, purpose: purpose)
        guard let answer = evaluate(.searchURL, request, answer: SearchURLAnswer.self) else { return nil }
        return URL(string: answer.url)
    }

    /// Which stored custom engines remain usable, and the selection that
    /// survives. Nil when the core cannot answer, so callers keep what they
    /// stored rather than discarding it.
    static func restoredCustomSearchProviders(
        _ providers: [BrowserCustomSearchProvider],
        selectedID: BrowserSearchProviderID
    ) -> (providers: [BrowserCustomSearchProvider], selectedID: BrowserSearchProviderID)? {
        let request = CustomProvidersRequest(
            selectedID: selectedID, providers: providers.map(BrowserCoreSearchProviderRecord.init))
        guard let answer = evaluate(.searchCustomProviders, request, answer: CustomProvidersAnswer.self),
            answer.indices.allSatisfy(providers.indices.contains)
        else { return nil }
        return (answer.indices.map { providers[$0] }, answer.selectedID)
    }

    // MARK: - Actions - Translation

    static func translationRule(in rules: BrowserAutomaticTranslationRules, sourceID: String)
        -> (rule: BrowserAutomaticTranslationRules.Rule?, target: String?)?
    {
        let request = TranslationRuleRequest(rules: rules, sourceID: sourceID)
        guard let answer = evaluate(.translationRule, request, answer: TranslationRuleAnswer.self) else { return nil }
        return (answer.rule, answer.target)
    }

    /// Whether each candidate names the same translation language as
    /// `language`. Nil when the core cannot answer.
    static func languageMatches(_ language: String, candidates: [String]) -> [Bool]? {
        var result: [Bool] = []
        for start in stride(from: 0, to: candidates.count, by: 256) {
            let batch = Array(candidates[start..<min(start + 256, candidates.count)])
            guard
                let matches = evaluate(
                    .translationMatches, LanguageMatchesRequest(language: language, candidates: batch),
                    answer: LanguageMatchesAnswer.self)?.matches,
                matches.count == batch.count
            else { return nil }
            result += matches
        }
        return result
    }
}
