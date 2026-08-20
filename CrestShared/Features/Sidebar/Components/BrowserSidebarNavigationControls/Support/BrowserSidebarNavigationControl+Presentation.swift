import SwiftUI

extension BrowserSidebarNavigationControl {
    var systemImage: String {
        switch self {
        case .back: "chevron.left"
        case .forward: "chevron.right"
        }
    }

    var accessibilityLabel: LocalizedStringKey {
        switch self {
        case .back: "Back"
        case .forward: "Forward"
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .back: "browser-back-control"
        case .forward: "browser-forward-control"
        }
    }

    /// The tooltip, with the keyboard equivalent every shell that has a
    /// keyboard honors.
    var tooltip: LocalizedStringKey {
        switch self {
        case .back: "Back (⌘[)"
        case .forward: "Forward (⌘])"
        }
    }

    var emptyHistoryTitle: LocalizedStringKey {
        switch self {
        case .back: "No Earlier Pages"
        case .forward: "No Later Pages"
        }
    }
}
