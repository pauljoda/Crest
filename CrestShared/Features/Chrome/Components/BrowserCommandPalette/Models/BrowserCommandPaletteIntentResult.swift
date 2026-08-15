import Foundation

struct BrowserCommandPaletteIntentResult: Sendable {
    let result: BrowserCommandPaletteResult
    let url: URL
    let isNavigation: Bool
}
