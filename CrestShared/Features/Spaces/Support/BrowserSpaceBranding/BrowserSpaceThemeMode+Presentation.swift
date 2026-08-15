import SwiftUI

extension BrowserSpaceThemeMode {
    var title: LocalizedStringKey {
        switch self {
        case .banner: "Banner"
        case .gradient: "Gradient"
        }
    }
}
