import Foundation

extension BrowserCommandPaletteResults {
    static func rank<Element>(
        _ elements: [Element],
        limit: Int,
        score: (Element) -> Int?
    ) -> [Element] {
        var scored: [(element: Element, score: Int, position: Int)] = []
        for (position, element) in elements.enumerated() {
            guard !Task.isCancelled else { return [] }
            guard let value = score(element) else { continue }
            scored.append((element, value, position))
        }
        return
            scored
            .sorted { lhs, rhs in
                lhs.score == rhs.score
                    ? lhs.position < rhs.position
                    : lhs.score > rhs.score
            }
            .prefix(limit)
            .map(\.element)
    }

    static func normalizedKey(_ url: URL) -> String {
        (BrowserHistoryURL.normalized(url) ?? url).absoluteString
    }
}
