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
    private let searchURLTemplate: String
    private let suggestionURLTemplate: String?

    static let google = builtIn(
        .google,
        title: "Google",
        search: "https://www.google.com/search?q=%s",
        suggestions: "https://www.google.com/complete/search?client=chrome&q=%s"
    )
    static let duckDuckGo = builtIn(
        .duckDuckGo,
        title: "DuckDuckGo",
        search: "https://duckduckgo.com/?q=%s",
        suggestions: "https://duckduckgo.com/ac/?q=%s&type=list"
    )
    static let bing = builtIn(
        .bing,
        title: "Bing",
        search: "https://www.bing.com/search?q=%s",
        suggestions: "https://www.bing.com/osjson.aspx?query=%s"
    )
    static let ecosia = builtIn(
        .ecosia,
        title: "Ecosia",
        search: "https://www.ecosia.org/search?q=%s",
        suggestions: "https://ac.ecosia.org/autocomplete?q=%s&type=list"
    )
    static let brave = builtIn(
        .brave,
        title: "Brave Search",
        search: "https://search.brave.com/search?q=%s",
        suggestions: "https://search.brave.com/api/suggest?q=%s"
    )

    static let allCases: [BrowserSearchProvider] = [
        .google, .duckDuckGo, .bing, .ecosia, .brave,
    ]

    var iconPageURL: URL? {
        guard builtIn == nil else { return nil }
        guard
            let components = URLComponents(
                string:
                    searchURLTemplate
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
        Self.render(searchURLTemplate, query: query)
    }

    func suggestionURL(for query: String) -> URL? {
        suggestionURLTemplate.flatMap { Self.render($0, query: query) }
    }

    static func provider(with id: BrowserSearchProviderID) -> BrowserSearchProvider? {
        allCases.first { $0.id == id }
    }

    private init(
        id: BrowserSearchProviderID,
        title: String,
        builtIn: BuiltIn?,
        searchURLTemplate: String,
        suggestionURLTemplate: String?
    ) {
        self.id = id
        self.title = title
        self.builtIn = builtIn
        self.searchURLTemplate = searchURLTemplate
        self.suggestionURLTemplate = suggestionURLTemplate
    }

    fileprivate init?(custom: BrowserCustomSearchProvider) {
        guard
            let name = try? BrowserSearchProviderTemplateValidator.validatedName(custom.name),
            let search = try? BrowserSearchProviderTemplateValidator.validatedTemplate(
                custom.searchURLTemplate
            )
        else { return nil }

        let suggestions: String?
        if let raw = custom.suggestionURLTemplate {
            guard
                let validated = try? BrowserSearchProviderTemplateValidator.validatedTemplate(raw)
            else { return nil }
            suggestions = validated
        } else {
            suggestions = nil
        }

        id = .custom(custom.id)
        title = name
        builtIn = nil
        searchURLTemplate = search
        suggestionURLTemplate = suggestions
    }

    private static func builtIn(
        _ builtIn: BuiltIn,
        title: String,
        search: String,
        suggestions: String
    ) -> BrowserSearchProvider {
        let id = BrowserSearchProviderID(rawValue: builtIn.rawValue) ?? .google
        return BrowserSearchProvider(
            id: id,
            title: title,
            builtIn: builtIn,
            searchURLTemplate: search,
            suggestionURLTemplate: suggestions
        )
    }

    private static func render(_ template: String, query: String) -> URL? {
        let encoded = query.addingPercentEncoding(
            withAllowedCharacters: CharacterSet(
                charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
            )
        )
        guard let encoded else { return nil }
        return URL(
            string:
                template
                .replacingOccurrences(of: "{searchTerms}", with: encoded)
                .replacingOccurrences(of: "%s", with: encoded)
        )
    }
}

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
    ) throws {
        self.id = id
        self.name = try BrowserSearchProviderTemplateValidator.validatedName(name)
        self.searchURLTemplate = try BrowserSearchProviderTemplateValidator.validatedTemplate(
            searchURLTemplate
        )
        let suggestions = suggestionURLTemplate?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        self.suggestionURLTemplate = try suggestions.flatMap {
            $0.isEmpty ? nil : try BrowserSearchProviderTemplateValidator.validatedTemplate($0)
        }
    }

    var provider: BrowserSearchProvider {
        BrowserSearchProvider(custom: self) ?? .google
    }

    var validatedProvider: BrowserSearchProvider? {
        BrowserSearchProvider(custom: self)
    }
}

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

private enum BrowserSearchProviderTemplateValidator {
    static func validatedName(_ value: String) throws -> String {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw BrowserCustomSearchProviderError.emptyName }
        guard value.count <= 64 else { throw BrowserCustomSearchProviderError.nameTooLong }
        return value
    }

    static func validatedTemplate(_ rawValue: String) throws -> String {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count <= 2_048 else {
            throw BrowserCustomSearchProviderError.templateTooLong
        }

        let percentCount = value.components(separatedBy: "%s").count - 1
        let openSearchCount = value.components(separatedBy: "{searchTerms}").count - 1
        let placeholderCount = percentCount + openSearchCount
        guard placeholderCount > 0 else {
            throw BrowserCustomSearchProviderError.missingPlaceholder
        }
        guard placeholderCount == 1 else {
            throw BrowserCustomSearchProviderError.ambiguousPlaceholder
        }
        try validatePercentEscapes(in: value)

        let probe =
            value
            .replacingOccurrences(of: "%s", with: "crest-template-probe")
            .replacingOccurrences(of: "{searchTerms}", with: "crest-template-probe")
        guard let components = URLComponents(string: probe), components.url != nil else {
            throw BrowserCustomSearchProviderError.invalidURL
        }
        guard components.scheme?.lowercased() == "https" else {
            throw BrowserCustomSearchProviderError.requiresHTTPS
        }
        guard components.user == nil, components.password == nil else {
            throw BrowserCustomSearchProviderError.credentialsNotAllowed
        }
        guard components.port == nil || components.port == 443 else {
            throw BrowserCustomSearchProviderError.unsupportedPort
        }
        guard
            let host = components.host?.lowercased(),
            !host.contains("crest-template-probe"),
            isPublicHost(host)
        else {
            throw BrowserCustomSearchProviderError.unsafeHost
        }

        if let fragment = value.split(separator: "#", maxSplits: 1).dropFirst().first,
            fragment.contains("%s") || fragment.contains("{searchTerms}")
        {
            throw BrowserCustomSearchProviderError.fragmentPlaceholderNotAllowed
        }

        let secretNames: Set<String> = [
            "token", "key", "apikey", "api_key", "access_token", "password",
            "credential", "credentials", "auth", "authorization",
        ]
        if components.queryItems?.contains(where: {
            secretNames.contains($0.name.lowercased())
        }) == true {
            throw BrowserCustomSearchProviderError.secretNotAllowed
        }
        return value
    }

    private static func isPublicHost(_ host: String) -> Bool {
        guard host.contains("."), !host.hasSuffix(".local") else { return false }
        guard host != "localhost", !host.hasSuffix(".localhost") else { return false }
        guard !host.contains(":") else { return false }
        let pieces = host.split(separator: ".")
        if pieces.count == 4, pieces.allSatisfy({ Int($0) != nil }) { return false }
        return true
    }

    private static func validatePercentEscapes(in value: String) throws {
        let scalars = Array(value.unicodeScalars)
        var index = 0
        while index < scalars.count {
            guard scalars[index] == "%" else {
                index += 1
                continue
            }
            if index + 1 < scalars.count, scalars[index + 1] == "s" {
                index += 2
                continue
            }
            guard
                index + 2 < scalars.count,
                isHexadecimal(scalars[index + 1]),
                isHexadecimal(scalars[index + 2])
            else {
                throw BrowserCustomSearchProviderError.invalidURL
            }
            index += 3
        }
    }

    private static func isHexadecimal(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 48...57, 65...70, 97...102: true
        default: false
        }
    }
}
