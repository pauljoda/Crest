struct BrowserCommandPaletteIndexedResult: Identifiable, Equatable, Sendable {
    let index: Int
    let result: BrowserCommandPaletteResult

    var id: String { result.id }
}
