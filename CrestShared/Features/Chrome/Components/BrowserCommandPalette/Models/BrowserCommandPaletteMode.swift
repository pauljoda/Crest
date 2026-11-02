import Foundation

/// What opened the palette: a new tab, or editing the address of the tab a
/// window shows, which starts the query at that address.
enum BrowserCommandPaletteMode: Equatable, Hashable, Sendable {
    case newTab
    case editLocation(String)

    // MARK: - Variables

    var initialQuery: String {
        switch self {
        case .newTab: ""
        case .editLocation(let address): address
        }
    }

    /// The query a palette opened this way over a page at `address` starts
    /// with, whatever address the mode carries.
    func initialQuery(over address: String) -> String {
        switch self {
        case .newTab: ""
        case .editLocation: address
        }
    }
}
