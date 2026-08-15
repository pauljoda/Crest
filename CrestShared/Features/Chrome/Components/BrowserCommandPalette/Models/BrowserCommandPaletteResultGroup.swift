struct BrowserCommandPaletteResultGroup: Identifiable, Equatable, Sendable {
    let id: String
    let header: String?
    let items: [BrowserCommandPaletteIndexedResult]
}
