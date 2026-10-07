import Foundation

/// What a find-in-page search has turned up so far.
struct BrowserFindMatchState: Hashable, Sendable {
    // MARK: - Types

    /// The color a state's words and symbol take, which the view that draws
    /// them names.
    enum Tones: Sendable {
        case quiet
        case success
        case failure
    }

    // MARK: - Static Variables

    /// No search has been asked for, so there is nothing to say.
    static let idle = BrowserFindMatchState(name: "idle", label: nil, symbol: nil)
    static let searching = BrowserFindMatchState(
        name: "searching", label: "Searching", symbol: nil, showsProgress: true)
    static let found = BrowserFindMatchState(
        name: "found", label: "Match found", symbol: "checkmark.circle.fill", tone: .success)
    static let notFound = BrowserFindMatchState(
        name: "notFound", label: "No match", symbol: "exclamationmark.circle.fill", tone: .failure)

    /// Every state.
    static let all: [BrowserFindMatchState] = [idle, searching, found, notFound]

    // MARK: - Variables

    let name: String

    /// The state in words, also its accessibility label where a symbol stands
    /// in for them.
    let label: LocalizedStringResource?

    /// The symbol that stands for the state where there is no room for words.
    let symbol: String?

    /// Whether a spinner stands for the state where there is no room for words.
    let showsProgress: Bool

    let tone: Tones

    // MARK: - Initializers

    private init(
        name: String, label: LocalizedStringResource?, symbol: String?, showsProgress: Bool = false,
        tone: Tones = .quiet
    ) {
        self.name = name
        self.label = label
        self.symbol = symbol
        self.showsProgress = showsProgress
        self.tone = tone
    }

    // MARK: - Actions - Identity

    static func == (lhs: BrowserFindMatchState, rhs: BrowserFindMatchState) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
