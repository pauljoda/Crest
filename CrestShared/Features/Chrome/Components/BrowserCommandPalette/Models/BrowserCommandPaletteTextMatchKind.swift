enum BrowserCommandPaletteTextMatchKind: Int, Comparable, Sendable {
    case contains = 300
    case wordPrefix = 700
    case prefix = 1_000

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
