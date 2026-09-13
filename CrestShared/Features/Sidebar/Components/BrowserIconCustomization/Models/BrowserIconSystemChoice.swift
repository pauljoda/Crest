import SwiftUI

struct BrowserIconSystemChoice: Identifiable {
    let symbol: String
    let title: LocalizedStringKey

    var id: String { symbol }
}
