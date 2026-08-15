import SwiftUI

extension BrowserSpaceBrandColorRole {
    var accessibilityIdentifierComponent: String {
        switch self {
        case .background: "background"
        case .primary: "primary"
        case .secondary: "secondary"
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .background: "Background"
        case .primary: "Primary"
        case .secondary: "Secondary"
        }
    }

    var addColorTitle: LocalizedStringKey {
        switch self {
        case .background: "Add Background Color"
        case .primary: "Add Primary Color"
        case .secondary: "Add Secondary Color"
        }
    }

    var removeColorTitle: LocalizedStringKey {
        switch self {
        case .background: "Remove Background Color"
        case .primary: "Remove Primary Color"
        case .secondary: "Remove Secondary Color"
        }
    }
}
