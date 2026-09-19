import SwiftUI

/// The desktop's rebindable command table.
struct BrowserPlatformShortcutSettingsPane: View {
    let shortcuts: BrowserShortcutStore
    let browser: BrowserStore
    let requestedSpaceID: SpaceID?
    let requestRevision: Int

    var body: some View {
        BrowserShortcutSettingsView(
            shortcuts: shortcuts,
            browser: browser,
            requestedSpaceID: requestedSpaceID,
            requestRevision: requestRevision
        )
    }
}
