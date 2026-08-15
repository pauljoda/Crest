import AppKit
import SwiftUI

enum BrowserSpaceEditorSection: String, CaseIterable, Identifiable {
    case appearance
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .appearance: "Appearance"
        case .settings: "Details"
        }
    }

    var symbol: String {
        switch self {
        case .appearance: "paintpalette"
        case .settings: "slider.horizontal.3"
        }
    }
}
