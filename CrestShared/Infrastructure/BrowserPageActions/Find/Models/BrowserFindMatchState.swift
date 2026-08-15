enum BrowserFindMatchState: Equatable, Sendable {
    case idle
    case searching
    case found
    case notFound

    var accessibilityLabel: String? {
        switch self {
        case .idle:
            nil
        case .searching:
            "Searching"
        case .found:
            "Match found"
        case .notFound:
            "No match"
        }
    }
}
