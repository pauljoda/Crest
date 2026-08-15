enum BrowserCommandPaletteResultPreparation {
    nonisolated static func prepare(
        for input: BrowserCommandPaletteInput
    ) -> BrowserCommandPalettePreparedResults {
        let results = BrowserCommandPaletteResults.results(for: input)
        return BrowserCommandPalettePreparedResults(
            query: input.query,
            results: results,
            groups: BrowserCommandPaletteResultGroupingPolicy.groups(
                results: results,
                query: input.query
            )
        )
    }
}
