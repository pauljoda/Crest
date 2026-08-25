import Foundation

struct BrowserCommandActionPresentation: Equatable, Sendable {
    let title: String
    let subtitle: String
    let symbol: String
    let url: URL

    init?(query: String, searchProvider: BrowserSearchProvider) {
        guard
            let intent = AddressResolver.intent(
                query,
                searchProvider: searchProvider
            )
        else {
            return nil
        }
        url = intent.url
        switch intent {
        case .open(let url):
            let host =
                url.host()?.replacingOccurrences(of: "www.", with: "")
                ?? url.absoluteString
            title = "Open \(host)"
            subtitle = url.absoluteString
            symbol = "globe"
        case .search(let query, let provider, _):
            title = "Search with \(provider.title)"
            subtitle = query
            symbol = "magnifyingglass"
        }
    }
}

struct BrowserCommandPaletteIndexedResult: Identifiable, Equatable, Sendable {
    let index: Int
    let result: BrowserCommandPaletteResult

    var id: String { result.id }
}

struct BrowserCommandPaletteIntentResult: Sendable {
    let result: BrowserCommandPaletteResult
    let url: URL
    let isNavigation: Bool
}

struct BrowserCommandPalettePreparedResults: Sendable {
    let query: String
    let results: [BrowserCommandPaletteResult]
    let groups: [BrowserCommandPaletteResultGroup]
}

struct BrowserCommandPaletteResult: Identifiable, Equatable, Sendable {
    let section: BrowserCommandPaletteSection?
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let searchProvider: BrowserSearchProvider?
    let trailing: String
    let target: BrowserCommandPaletteTarget

    init(
        section: BrowserCommandPaletteSection?,
        id: String,
        title: String,
        subtitle: String,
        symbol: String,
        searchProvider: BrowserSearchProvider? = nil,
        trailing: String,
        target: BrowserCommandPaletteTarget
    ) {
        self.section = section
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.searchProvider = searchProvider
        self.trailing = trailing
        self.target = target
    }

    var isIntent: Bool { section == nil }

    var faviconTabID: TabID? {
        switch target {
        case .tab(let assignment): assignment.tabID
        case .url, .command: nil
        }
    }
}

struct BrowserCommandPaletteResultGroup: Identifiable, Equatable, Sendable {
    let id: String
    let header: String?
    let items: [BrowserCommandPaletteIndexedResult]
}

enum BrowserCommandPaletteResultLimits {
    static let searchSuggestions = 3
    static let restingTabs = 5
    static let matchedTabs = 8
    static let restingActions = 3
    static let matchedActions = 5
    static let saved = 5
    static let history = 6
    static let historyScan = 1_500
    static let historyCandidates = 40
    static let initialResultCapacity = 24
    static let folderMatchPenalty = 50
    static let maximumHistoryRecencyBonus = 120
    static let historyRecencyDecayInterval = 8
    static let maximumHistoryRepetitionBonus = 60
    static let historyVisitBonus = 4
}

enum BrowserCommandPaletteSection: String, CaseIterable, Sendable {
    case searchSuggestions
    case tabs
    case actions
    case saved
    case history

    var title: String {
        switch self {
        case .searchSuggestions: "Search Suggestions"
        case .tabs: "Tabs"
        case .actions: "Actions"
        case .saved: "Pinned & Saved"
        case .history: "History"
        }
    }

    static let openTabsTitle = "Open Tabs"
}

enum BrowserCommandPaletteTarget: Equatable, Hashable, Sendable {
    case tab(BrowserTabRuntimeAssignment)
    case url(URL)
    case command(BrowserShortcutCommand)
}
