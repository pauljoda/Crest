enum BrowserCommandPaletteMode: Equatable, Hashable, Sendable {
    case newTab
    case editLocation(String)

    var initialQuery: String {
        switch self {
        case .newTab:
            ""
        case .editLocation(let address):
            address
        }
    }
}
