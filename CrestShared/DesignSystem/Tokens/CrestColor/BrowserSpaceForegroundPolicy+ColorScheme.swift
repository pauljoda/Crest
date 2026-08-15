import SwiftUI

extension BrowserSpaceForegroundPolicy {
    static func colorScheme(for branding: BrowserSpaceBranding) -> ColorScheme {
        tone(for: branding) == .light ? .dark : .light
    }
}
