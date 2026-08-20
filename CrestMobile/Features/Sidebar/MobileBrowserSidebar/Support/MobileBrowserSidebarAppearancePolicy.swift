import SwiftUI

enum MobileBrowserSidebarAppearancePolicy {
    /// Whether the sidebar reads its foreground from the Space's own branding
    /// rather than from the system appearance. Every compact placement does, so
    /// the rule is what keeps them agreeing rather than a per-placement choice.
    static func usesSpaceForeground() -> Bool {
        true
    }
}
