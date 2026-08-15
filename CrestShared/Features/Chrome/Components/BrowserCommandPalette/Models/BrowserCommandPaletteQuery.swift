import Foundation

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
