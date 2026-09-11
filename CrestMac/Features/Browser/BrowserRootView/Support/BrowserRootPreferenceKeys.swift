import SwiftUI

enum BrowserRootPreferenceKeys {
    static let sidebarWidth = "crest.sidebar.width.mac"
}

struct BrowserRootPageBoundsKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}
