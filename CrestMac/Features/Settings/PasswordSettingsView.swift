import SwiftUI

/// The desktop's Passwords pane.
///
/// Everything this pane draws is now ``BrowserPasswordSettingsPane``; what stays here
/// is the one thing only the desktop has — a Settings window with its own search
/// field, whose query filters this pane's list. Touch runs the same pane behind a
/// sheet and hands it that sheet's own search field instead.
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
