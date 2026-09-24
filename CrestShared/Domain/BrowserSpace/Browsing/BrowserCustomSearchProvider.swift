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

/// The rule a custom engine breaks, with the explanation the editor shows.
enum BrowserCustomSearchProviderError: LocalizedError, Equatable {
    case emptyName
    case nameTooLong
    case templateTooLong
    case missingPlaceholder
    case ambiguousPlaceholder
    case invalidURL
    case requiresHTTPS
    case unsafeHost
    case unsupportedPort
    case credentialsNotAllowed
    case fragmentPlaceholderNotAllowed
    case secretNotAllowed
    case duplicateName
    case tooManyProviders

    /// The core's refusal of a custom engine. Any other refusal reads as an
    /// invalid template.
    init(_ rejection: Rejection) {
        self =
            switch rejection {
            case .invalidSearchEngine(let invalid):
                switch invalid.flaw {
                case .emptyName: .emptyName
                case .nameTooLong: .nameTooLong
                case .templateTooLong: .templateTooLong
                case .missingPlaceholder: .missingPlaceholder
                case .ambiguousPlaceholder: .ambiguousPlaceholder
                case .invalidIdentity, .invalidTemplate: .invalidURL
                case .requiresHttps: .requiresHTTPS
                case .unsafeHost: .unsafeHost
                case .nonstandardPort: .unsupportedPort
                case .credentialsInTemplate: .credentialsNotAllowed
                case .placeholderInFragment: .fragmentPlaceholderNotAllowed
                case .secretInTemplate: .secretNotAllowed
                }
            case .duplicateSearchEngineName: .duplicateName
            case .searchEngineLimitReached: .tooManyProviders
            default: .invalidURL
            }
    }

    var errorDescription: String? {
        switch self {
        case .emptyName: String(localized: "Enter a name for this search engine.")
        case .nameTooLong:
            String(localized: "Search engine names must be 64 characters or fewer.")
        case .templateTooLong:
            String(localized: "URL templates must be 2,048 characters or fewer.")
        case .missingPlaceholder:
            String(localized: "Include exactly one %s or {searchTerms} query placeholder.")
        case .ambiguousPlaceholder:
            String(localized: "Use exactly one query placeholder.")
        case .invalidURL: String(localized: "Enter a valid URL template.")
        case .requiresHTTPS:
            String(localized: "Search engine templates must use HTTPS.")
        case .unsafeHost:
            String(
                localized:
                    "Use a public search engine host, not a local or numeric address."
            )
        case .unsupportedPort:
            String(
                localized:
                    "Search engine templates may only use the standard HTTPS port."
            )
        case .credentialsNotAllowed:
            String(
                localized:
                    "Usernames and passwords cannot be stored in a search template."
            )
        case .fragmentPlaceholderNotAllowed:
            String(
                localized:
                    "Put the query placeholder in the path or query, not the fragment."
            )
        case .secretNotAllowed:
            String(
                localized:
                    "Authentication tokens and other secrets cannot be stored in a search template. Sign in on the search engine website instead."
            )
        case .duplicateName:
            String(localized: "A custom search engine already uses this name.")
        case .tooManyProviders:
            String(localized: "A Space can contain up to 32 custom search engines.")
        }
    }
}
