import SwiftUI

enum BrowserManualSetupPlacementPresentation {
    static let choices: [TabPlacement] = [.pinned, .saved, .current]

    static func title(for placement: TabPlacement) -> String {
        switch placement {
        case .pinned: "Pinned"
        case .saved: "Saved"
        case .current: "Open"
        }
    }

    static func label(for placement: TabPlacement) -> LocalizedStringKey {
        switch placement {
        case .pinned: "Pinned"
        case .saved: "Saved"
        case .current: "Open"
        }
    }

    static func symbol(for placement: TabPlacement) -> String {
        switch placement {
        case .pinned: "pin.fill"
        case .saved: "bookmark.fill"
        case .current: "rectangle.stack.fill"
        }
    }
}
