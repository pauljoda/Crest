import SwiftUI

/// The desktop's Passwords pane.
///
/// Everything this pane draws is now ``BrowserPasswordSettingsPane``; what stays here
/// is the one thing only the desktop has — a Settings window with its own search
/// field, whose query filters this pane's list. Touch searches the list inside the
/// sheet that owns it, so it passes no query at all.
struct PasswordSettingsView: View {
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    @Binding var searchText: String

    var body: some View {
        BrowserPasswordSettingsPane(
            browser: browser,
            spaceAccess: spaceAccess,
            layout: .macOSPage,
            searchText: $searchText
        )
    }
}
