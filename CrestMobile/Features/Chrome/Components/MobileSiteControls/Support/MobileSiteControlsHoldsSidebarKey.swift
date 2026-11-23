import SwiftUI

/// Whether Site Controls show from a control in the sidebar, which keeps a
/// floating sidebar from going away under them and taking their anchor.
struct MobileSiteControlsHoldsSidebarKey: PreferenceKey {
    static let defaultValue = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}
