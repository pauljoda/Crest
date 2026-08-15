extension BrowserCommandPaletteResults {
    static func otherSpaceResults(
        query: BrowserCommandPaletteQuery,
        spaces: [BrowserSpace]
    ) -> [BrowserCommandPaletteResult] {
        guard !query.isEmpty, !spaces.isEmpty else { return [] }

        var scored: [(BrowserCommandPaletteResult, Int)] = []
        for space in spaces {
            for tab in space.tabs where !tab.isStartPage {
                guard !Task.isCancelled else { return [] }
                guard
                    let score = BrowserCommandPaletteText.score(
                        query,
                        title: tab.displayTitle,
                        detail: tab.url?.absoluteString
                            ?? tab.savedSiteURL?.absoluteString
                            ?? ""
                    )
                else { continue }
                scored.append(
                    (
                        BrowserCommandPaletteResult(
                            section: .otherSpaces,
                            id:
                                "space-\(space.id.id.uuidString)-profile-\(space.profile.id.uuidString)-tab-\(tab.id.id.uuidString)",
                            title: tab.displayTitle,
                            subtitle: tab.url?.host() ?? tab.url?.absoluteString ?? "",
                            symbol: "globe",
                            trailing: space.name,
                            target: .spaceTab(
                                BrowserTabRuntimeAssignment(
                                    tabID: tab.id,
                                    spaceID: space.id,
                                    profileID: space.profile.id
                                )
                            )
                        ),
                        score
                    ))
            }
        }

        return
            scored
            .enumerated()
            .sorted { lhs, rhs in
                lhs.element.1 == rhs.element.1
                    ? lhs.offset < rhs.offset
                    : lhs.element.1 > rhs.element.1
            }
            .prefix(BrowserCommandPaletteResultLimits.otherSpaceTabs)
            .map(\.element.0)
    }
}
