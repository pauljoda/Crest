enum BrowserCommandPaletteResults {
    static func results(
        for input: BrowserCommandPaletteInput
    ) -> [BrowserCommandPaletteResult] {
        if let omnibox = input.omnibox {
            return omniboxResults(for: omnibox)
        }

        let query = BrowserCommandPaletteQuery(input.query)
        let intent = intentResult(
            query: query,
            searchProvider: input.searchProvider
        )

        var results: [BrowserCommandPaletteResult] = []
        results.reserveCapacity(BrowserCommandPaletteResultLimits.initialResultCapacity)

        if let intent {
            results.append(intent.result)
        }

        results.append(contentsOf: tabResults(query: query, input: input))
        guard !Task.isCancelled else { return [] }
        results.append(
            contentsOf: actionResults(
                query: query,
                commands: input.commands
            ))
        guard !Task.isCancelled else { return [] }
        results.append(contentsOf: savedResults(query: query, space: input.space))
        guard !Task.isCancelled else { return [] }

        var claimedURLs = Set<String>(
            minimumCapacity: (input.space?.tabs.count ?? 0) + 1
        )
        for tab in input.space?.tabs ?? [] {
            if let url = tab.url {
                claimedURLs.insert(normalizedKey(url))
            }
        }
        if let intent {
            claimedURLs.insert(normalizedKey(intent.url))
        }

        results.append(
            contentsOf: historyResults(
                query: query,
                space: input.space,
                claimedURLs: claimedURLs
            ))
        guard !Task.isCancelled else { return [] }
        results.append(
            contentsOf: otherSpaceResults(
                query: query,
                spaces: input.otherSpaces
            ))

        return results
    }
}
