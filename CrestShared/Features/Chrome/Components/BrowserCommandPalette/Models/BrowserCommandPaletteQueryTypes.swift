import Foundation

struct BrowserCommandPaletteInput: Sendable {
    var query: String
    var space: BrowserSpace?
    var selectedTabID: TabID?
    var commands: [BrowserShortcutCommand]
    var searchProvider: BrowserSearchProvider

    init(
        query: String,
        space: BrowserSpace?,
        selectedTabID: TabID? = nil,
        commands: [BrowserShortcutCommand] = [],
        searchProvider: BrowserSearchProvider = .google
    ) {
        self.query = query
        self.space = space
        self.selectedTabID = selectedTabID
        self.commands = commands
        self.searchProvider = searchProvider
    }
}

enum BrowserCommandPaletteMode: Equatable, Hashable, Sendable {
    case newTab
    case editLocation(String)

    var initialQuery: String {
        switch self {
        case .newTab:
            ""
        case .editLocation(let address):
            address
        }
    }
}

/// A query folded once so every result candidate can use the same scalar terms.
struct BrowserCommandPaletteQuery: Equatable, Sendable {
    let text: String
    let terms: [[Unicode.Scalar]]

    var isEmpty: Bool { terms.isEmpty }

    init(_ raw: String) {
        text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var terms: [[Unicode.Scalar]] = []
        var current: [Unicode.Scalar] = []
        for scalar in text.unicodeScalars {
            if BrowserCommandPaletteText.isWhitespace(scalar) {
                if !current.isEmpty {
                    terms.append(current)
                    current = []
                }
                continue
            }
            current.append(BrowserCommandPaletteText.folded(scalar))
        }
        if !current.isEmpty { terms.append(current) }
        self.terms = terms
    }
}

enum BrowserCommandPaletteTextMatchKind: Int, Comparable, Sendable {
    case contains = 300
    case wordPrefix = 700
    case prefix = 1_000

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
