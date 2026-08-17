import SwiftUI

/// Where a link that arrives from outside a page ends up.
struct BrowserLinkSettingsPane: View {
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController

    @State private var links: BrowserLinkPreferenceStore

    init(
        browser: BrowserStore,
        spaceAccess: BrowserSpaceAccessController,
        links: BrowserLinkPreferenceStore = .shared
    ) {
        self.browser = browser
        self.spaceAccess = spaceAccess
        _links = State(initialValue: links)
    }

    var body: some View {
        BrowserSettingsPane(.links) {
            BrowserLinkSettingsContent(
                browser: browser,
                spaceAccess: spaceAccess,
                links: links
            )
        }
    }
}
