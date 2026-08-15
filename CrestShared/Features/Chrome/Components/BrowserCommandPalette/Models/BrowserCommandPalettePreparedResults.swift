struct BrowserCommandPalettePreparedResults: Sendable {
    let query: String
    let results: [BrowserCommandPaletteResult]
    let groups: [BrowserCommandPaletteResultGroup]
}
