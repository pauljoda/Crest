import SwiftUI

enum BrowserNavigationFailureLayout: Equatable, Sendable {
    case compact
    case regular

    var contentAlignment: HorizontalAlignment {
        self == .compact ? .center : .leading
    }

    var frameAlignment: Alignment {
        self == .compact ? .center : .leading
    }

    var textAlignment: TextAlignment {
        self == .compact ? .center : .leading
    }

    var horizontalPadding: CGFloat {
        self == .compact
            ? BrowserNavigationFailureMetrics.compactHorizontalPadding
            : BrowserNavigationFailureMetrics.regularHorizontalPadding
    }

    var verticalPadding: CGFloat {
        self == .compact
            ? BrowserNavigationFailureMetrics.compactVerticalPadding
            : BrowserNavigationFailureMetrics.regularVerticalPadding
    }
}
