extension BrowserCommandPaletteText {
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
