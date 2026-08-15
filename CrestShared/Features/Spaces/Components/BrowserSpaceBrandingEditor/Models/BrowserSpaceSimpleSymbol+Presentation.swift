import SwiftUI

extension BrowserSpaceSimpleSymbol {
    var titleKey: LocalizedStringKey {
        switch self {
        case .work: "Work"
        case .personal: "Personal"
        case .home: "Home"
        case .study: "Study"
        case .creative: "Creative"
        case .games: "Games"
        case .travel: "Travel"
        case .grid: "Grid"
        }
    }
}
