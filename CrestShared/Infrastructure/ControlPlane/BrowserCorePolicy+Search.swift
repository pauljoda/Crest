import Foundation

enum BrowserSearchQueryPurpose: String {
    case search
    case suggestions
}

extension BrowserSearchProvider {
    /// How the core names this engine: a built-in identity, or a custom engine
    /// with its stored templates, which the core validates before use.
    var coreDescriptor: [String: Any] {
        guard builtIn == nil else { return ["id": id.rawValue] }
        return [
            "id": id.rawValue, "name": title,
            "searchURLTemplate": customSearchURLTemplate ?? "",
            "suggestionURLTemplate": customSuggestionURLTemplate as Any? ?? NSNull(),
        ]
    }
}

extension BrowserCustomSearchProvider {
    var coreRecord: [String: Any] {
        [
            "id": id.uuidString.lowercased(), "name": name, "searchURLTemplate": searchURLTemplate,
            "suggestionURLTemplate": suggestionURLTemplate as Any? ?? NSNull(),
        ]
    }

    init?(coreRecord: [String: Any]) {
        guard let rawID = coreRecord["id"] as? String, let id = UUID(uuidString: rawID),
            let name = coreRecord["name"] as? String,
            let search = coreRecord["searchURLTemplate"] as? String
        else { return nil }
        self.init(id: id, name: name, searchURLTemplate: search,
            suggestionURLTemplate: coreRecord["suggestionURLTemplate"] as? String)
    }
}

/// Search and translation decisions owned by the portable core.
extension BrowserCorePolicy {
    /// The results or suggestion URL for a query. Nil when the engine has no
    /// suggestion endpoint or the core cannot answer.
    static func searchURL(provider: BrowserSearchProvider, query: String,
        purpose: BrowserSearchQueryPurpose) -> URL? {
        guard let text = evaluate([
            "version": 1, "operation": "search.url", "searchProvider": provider.coreDescriptor,
            "query": query, "purpose": purpose.rawValue,
        ])?["url"] as? String else { return nil }
        return URL(string: text)
    }

    /// The normalized custom engine the core would save, or the rule it breaks.
    static func admittedCustomSearchProvider(_ provider: BrowserCustomSearchProvider,
        existing: [BrowserCustomSearchProvider]) throws -> BrowserCustomSearchProvider {
        guard let response = evaluate([
            "version": 1, "operation": "search.custom_provider", "provider": provider.coreRecord,
            "existing": existing.map { ["id": $0.id.uuidString.lowercased(), "name": $0.name] },
        ]) else { throw BrowserCustomSearchProviderError.invalidURL }
        if let code = response["error"] as? String {
            throw BrowserCustomSearchProviderError(rawValue: code) ?? .invalidURL
        }
        guard let record = response["provider"] as? [String: Any],
            let admitted = BrowserCustomSearchProvider(coreRecord: record)
        else { throw BrowserCustomSearchProviderError.invalidURL }
        return admitted
    }

    /// Which stored custom engines remain usable, and the selection that
    /// survives. Nil when the core cannot answer, so callers keep what they
    /// stored rather than discarding it.
    static func restoredCustomSearchProviders(_ providers: [BrowserCustomSearchProvider],
        selectedID: BrowserSearchProviderID) -> (providers: [BrowserCustomSearchProvider], selectedID: BrowserSearchProviderID)? {
        guard let response = evaluate([
            "version": 1, "operation": "search.custom_providers", "selectedID": selectedID.rawValue,
            "providers": providers.map(\.coreRecord),
        ]), let indices = response["indices"] as? [Int],
            indices.allSatisfy(providers.indices.contains),
            let selected = (response["selectedID"] as? String).flatMap(BrowserSearchProviderID.init(rawValue:))
        else { return nil }
        return (indices.map { providers[$0] }, selected)
    }

    static func translationRule(in rules: BrowserAutomaticTranslationRules, sourceID: String)
        -> (rule: BrowserAutomaticTranslationRules.Rule?, target: String?)? {
        guard let response = evaluate([
            "version": 1, "operation": "translation.rule", "rules": rules.coreValue, "sourceID": sourceID,
        ]) else { return nil }
        return ((response["rule"] as? [String: Any]).flatMap(BrowserAutomaticTranslationRules.Rule.init(coreValue:)),
            response["target"] as? String)
    }

    /// Whether each candidate names the same translation language as
    /// `language`. Nil when the core cannot answer.
    static func languageMatches(_ language: String, candidates: [String]) -> [Bool]? {
        var result: [Bool] = []
        for start in stride(from: 0, to: candidates.count, by: 256) {
            let batch = Array(candidates[start..<min(start + 256, candidates.count)])
            guard let matches = evaluate([
                "version": 1, "operation": "translation.matches", "language": language, "candidates": batch,
            ])?["matches"] as? [Bool], matches.count == batch.count else { return nil }
            result += matches
        }
        return result
    }
}

private extension BrowserAutomaticTranslationRules {
    var coreValue: [String: Any] {
        ["sources": sources.mapValues { ["targetID": $0.targetID, "isEnabled": $0.isEnabled] }]
    }
}

private extension BrowserAutomaticTranslationRules.Rule {
    init?(coreValue: [String: Any]) {
        guard let target = coreValue["targetID"] as? String, let enabled = coreValue["isEnabled"] as? Bool else { return nil }
        self.init(targetID: target, isEnabled: enabled)
    }
}
