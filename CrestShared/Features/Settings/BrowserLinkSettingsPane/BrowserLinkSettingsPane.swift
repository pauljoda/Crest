import SwiftUI

/// Where a link that arrives from outside a page ends up.
struct BrowserLinkSettingsPane: View {
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    /// Opens a sample Peek over Settings, for a shell that can show one there.
    var testPeek: (() -> Void)? = nil

    var body: some View {
        BrowserSettingsPane(.links) {
            BrowserLinkSettingsContent(
                browser: browser, spaceAccess: spaceAccess, links: browser.linkPreferences, testPeek: testPeek)
        }
    }
}
