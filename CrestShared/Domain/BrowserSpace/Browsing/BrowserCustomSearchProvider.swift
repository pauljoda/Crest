import Foundation

/// A Space's custom search engine as persisted and synced. The core validates
/// it when it is saved and again before any of its templates is used.
struct BrowserCustomSearchProvider: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let searchURLTemplate: String
    let suggestionURLTemplate: String?

    init(
        id: UUID = UUID(),
        name: String,
        searchURLTemplate: String,
        suggestionURLTemplate: String? = nil
    ) {
        self.id = id
        self.name = name
        self.searchURLTemplate = searchURLTemplate
        self.suggestionURLTemplate = suggestionURLTemplate
    }

    /// The engine the core admitted.
    init(_ engine: CustomSearchEngine) {
        self.init(
            id: engine.id, name: engine.name, searchURLTemplate: engine.searchTemplate,
            suggestionURLTemplate: engine.suggestionTemplate)
    }

    var provider: SearchProvider { SearchProvider(custom: self) }

    /// This engine as the core's custom-engine rules read it.
    var engine: CustomSearchEngine {
        CustomSearchEngine(
            id: id, name: name, searchTemplate: searchURLTemplate, suggestionTemplate: suggestionURLTemplate)
    }
}

/// The core's refusal of a custom engine, with the explanation the editor
/// shows. A flaw explains itself, as does a duplicate name or the Space's
/// limit; any other refusal reads as an invalid template.
struct BrowserCustomSearchProviderError: LocalizedError, Equatable {
    let errorDescription: String?

    init(_ rejection: Rejection) {
        errorDescription =
            switch rejection {
            case .invalidSearchEngine(let invalid): String(localized: invalid.flaw.message)
            default: String(localized: rejection.message ?? SearchEngineFlaw.invalidTemplate.message)
            }
    }
}
