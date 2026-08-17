enum BrowserCommandPaletteText {
    static let detailPenalty = 150

    // MARK: - Folding

    private static let finalSigma: Unicode.Scalar = "ς"
    private static let sigma: Unicode.Scalar = "σ"

    static func folded(_ scalar: Unicode.Scalar) -> Unicode.Scalar {
        if scalar.isASCII {
            guard scalar.value >= 65, scalar.value <= 90 else { return scalar }
            return Unicode.Scalar(scalar.value + 32) ?? scalar
        }
        if scalar == finalSigma { return sigma }
        guard
            scalar.properties.isUppercase,
            let lowered = scalar.properties.lowercaseMapping.unicodeScalars.first
        else {
            return scalar
        }
        return lowered
    }

    static func isWhitespace(_ scalar: Unicode.Scalar) -> Bool {
        scalar.isASCII
            ? scalar.value == 32 || scalar.value == 9
            : scalar.properties.isWhitespace
    }

    static func isBoundary(_ scalar: Unicode.Scalar) -> Bool {
        if scalar.isASCII {
            let value = scalar.value
            let isDigit = value >= 48 && value <= 57
            let isUppercase = value >= 65 && value <= 90
            let isLowercase = value >= 97 && value <= 122
            return !(isDigit || isUppercase || isLowercase)
        }
        return !(scalar.properties.isAlphabetic || scalar.properties.numericType != nil)
    }

    // MARK: - Matching

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

    // MARK: - Scoring

    static func score(
        _ query: BrowserCommandPaletteQuery,
        title: String,
        detail: String = ""
    ) -> Int? {
        guard !query.isEmpty else { return nil }
        var total = 0
        for term in query.terms {
            if let kind = matchKind(of: term, in: title) {
                total += kind.rawValue
                continue
            }
            if !detail.isEmpty, let kind = matchKind(of: term, in: detail) {
                total += max(0, kind.rawValue - detailPenalty)
                continue
            }
            return nil
        }
        return total / query.terms.count
    }
}
