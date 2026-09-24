import Foundation

enum BrowserSearchProviderID: Codable, Equatable, Hashable, Sendable {
    case google
    case duckDuckGo
    case bing
    case ecosia
    case brave
    case custom(UUID)

    init?(rawValue: String) {
        switch rawValue {
        case "google": self = .google
        case "duckDuckGo": self = .duckDuckGo
        case "bing": self = .bing
        case "ecosia": self = .ecosia
        case "brave": self = .brave
        default:
            let prefix = "custom:"
            guard
                rawValue.hasPrefix(prefix),
                let id = UUID(uuidString: String(rawValue.dropFirst(prefix.count)))
            else { return nil }
            self = .custom(id)
        }
    }

    var rawValue: String {
        switch self {
        case .google: "google"
        case .duckDuckGo: "duckDuckGo"
        case .bing: "bing"
        case .ecosia: "ecosia"
        case .brave: "brave"
        case .custom(let id): "custom:\(id.uuidString.lowercased())"
        }
    }

    var isCustom: Bool {
        if case .custom = self { return true }
        return false
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        guard let value = Self(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown search provider identifier."
            )
        }
        self = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// A search engine as the UI shows it. The portable core owns the built-in
/// catalog, template validation and query construction; this projection keeps
/// the title and icon source, plus a custom engine's stored templates.
struct BrowserSearchProvider: Equatable, Hashable, Identifiable, Sendable {
    enum BuiltIn: String, CaseIterable, Sendable {
        case google
        case duckDuckGo
        case bing
        case ecosia
        case brave
    }

    let id: BrowserSearchProviderID
    let title: String
    let builtIn: BuiltIn?
    /// A custom engine's stored templates; nil for built-ins, whose templates
    /// live in the core catalog.
    let customSearchURLTemplate: String?
    let customSuggestionURLTemplate: String?

    static let google = BrowserSearchProvider(builtIn: .google, title: "Google")
    static let duckDuckGo = BrowserSearchProvider(builtIn: .duckDuckGo, title: "DuckDuckGo")
    static let bing = BrowserSearchProvider(builtIn: .bing, title: "Bing")
    static let ecosia = BrowserSearchProvider(builtIn: .ecosia, title: "Ecosia")
    static let brave = BrowserSearchProvider(builtIn: .brave, title: "Brave Search")

    static let allCases: [BrowserSearchProvider] = [
        .google, .duckDuckGo, .bing, .ecosia, .brave,
    ]

    /// The website a custom engine's favicon is loaded from.
    var iconPageURL: URL? {
        guard builtIn == nil, let template = customSearchURLTemplate else { return nil }
        guard
            let components = URLComponents(
                string:
                    template
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

    func searchURL(for query: String) -> URL? {
        BrowserCorePolicy.searchURL(provider: self, query: query, purpose: .search)
    }

    func suggestionURL(for query: String) -> URL? {
        BrowserCorePolicy.searchURL(provider: self, query: query, purpose: .suggestions)
    }

    static func provider(with id: BrowserSearchProviderID) -> BrowserSearchProvider? {
        allCases.first { $0.id == id }
    }

    fileprivate init(custom: BrowserCustomSearchProvider) {
        id = .custom(custom.id)
        title = custom.name
        builtIn = nil
        customSearchURLTemplate = custom.searchURLTemplate
        customSuggestionURLTemplate = custom.suggestionURLTemplate
    }

    private init(builtIn: BuiltIn, title: String) {
        id = BrowserSearchProviderID(rawValue: builtIn.rawValue) ?? .google
        self.title = title
        self.builtIn = builtIn
        customSearchURLTemplate = nil
        customSuggestionURLTemplate = nil
    }
}

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

    var provider: BrowserSearchProvider { BrowserSearchProvider(custom: self) }

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
