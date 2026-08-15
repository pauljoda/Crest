extension BrowserCommandPaletteResults {
    static func tabResults(
        query: BrowserCommandPaletteQuery,
        input: BrowserCommandPaletteInput
    ) -> [BrowserCommandPaletteResult] {
        guard let space = input.space else { return [] }
        let open = space.tabs.filter {
            $0.id != input.selectedTabID && !$0.isStartPage
        }
        guard !query.isEmpty else {
            return open.prefix(BrowserCommandPaletteResultLimits.restingTabs).map {
                tabResult($0, in: space, section: .tabs)
            }
        }
        let candidates = open.filter { $0.placement == .current }
        return rank(
            candidates,
            limit: BrowserCommandPaletteResultLimits.matchedTabs
        ) { tab in
            BrowserCommandPaletteText.score(
                query,
                title: tab.displayTitle,
                detail: tab.url?.absoluteString ?? ""
            )
        }
        .map { tabResult($0, in: space, section: .tabs) }
    }

    static func tabResult(
        _ tab: BrowserTab,
        in space: BrowserSpace,
        section: BrowserCommandPaletteSection
    ) -> BrowserCommandPaletteResult {
        BrowserCommandPaletteResult(
            section: section,
            id: "tab-\(tab.id.id.uuidString)",
            title: tab.displayTitle,
            subtitle: tab.url?.host() ?? tab.url?.absoluteString ?? "",
            symbol: "globe",
            trailing: "Switch to Tab",
            target: .tab(
                BrowserTabRuntimeAssignment(
                    tabID: tab.id,
                    spaceID: space.id,
                    profileID: space.profile.id
                )
            )
        )
    }
}
