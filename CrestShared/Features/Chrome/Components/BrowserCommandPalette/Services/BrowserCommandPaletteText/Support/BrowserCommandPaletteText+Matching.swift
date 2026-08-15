extension BrowserCommandPaletteText {
    static func matchKind(
        of needle: [Unicode.Scalar],
        in haystack: String
    ) -> BrowserCommandPaletteTextMatchKind? {
        guard !needle.isEmpty else { return nil }
        let scalars = haystack.unicodeScalars
        var best: BrowserCommandPaletteTextMatchKind?
        var index = scalars.startIndex
        var previous: Unicode.Scalar?

        while index != scalars.endIndex {
            if folded(scalars[index]) == needle[0],
                matches(needle, in: scalars, from: index)
            {
                let kind: BrowserCommandPaletteTextMatchKind =
                    if let previous {
                        isBoundary(previous) ? .wordPrefix : .contains
                    } else {
                        .prefix
                    }
                if kind == .prefix { return .prefix }
                if let currentBest = best {
                    best = max(currentBest, kind)
                } else {
                    best = kind
                }
                if best == .wordPrefix { return .wordPrefix }
            }
            previous = scalars[index]
            index = scalars.index(after: index)
        }
        return best
    }

    private static func matches(
        _ needle: [Unicode.Scalar],
        in scalars: String.UnicodeScalarView,
        from start: String.UnicodeScalarView.Index
    ) -> Bool {
        var index = start
        var position = 0
        while position < needle.count {
            guard index != scalars.endIndex,
                folded(scalars[index]) == needle[position]
            else { return false }
            index = scalars.index(after: index)
            position += 1
        }
        return true
    }
}
