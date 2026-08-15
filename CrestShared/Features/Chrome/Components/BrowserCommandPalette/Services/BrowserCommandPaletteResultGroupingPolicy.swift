import Foundation

enum BrowserCommandPaletteResultGroupingPolicy {
    static func groups(
        results: [BrowserCommandPaletteResult],
        query: String
    ) -> [BrowserCommandPaletteResultGroup] {
        var groups: [BrowserCommandPaletteResultGroup] = []
        for (index, result) in results.enumerated() {
            let item = BrowserCommandPaletteIndexedResult(index: index, result: result)
            let id = groupID(for: result)
            if let last = groups.last, last.id == id {
                groups[groups.count - 1] = BrowserCommandPaletteResultGroup(
                    id: last.id,
                    header: last.header,
                    items: last.items + [item]
                )
                continue
            }
            groups.append(
                BrowserCommandPaletteResultGroup(
                    id: id,
                    header: header(for: result, query: query),
                    items: [item]
                ))
        }
        return groups
    }

    private static func groupID(for result: BrowserCommandPaletteResult) -> String {
        result.section?.rawValue ?? "intent"
    }

    private static func header(
        for result: BrowserCommandPaletteResult,
        query: String
    ) -> String? {
        guard let section = result.section else { return nil }
        guard section == .tabs else { return section.title }
        return query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? BrowserCommandPaletteSection.openTabsTitle
            : section.title
    }
}
