import SwiftUI

extension BrowserSpaceForegroundTone {
    // MARK: - Variables

    /// The color scheme whose text draws in this tone: light text reads as a
    /// dark scheme.
    var colorScheme: ColorScheme {
        self == .light ? .dark : .light
    }
}
