import SwiftUI

/// Touch keeps the saved-password manager in a sheet because a phone has no
/// second column for a searchable credential list.
struct MobileCredentialSettingsView: View {
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController

    @State private var presentsPasswords = false

    var body: some View {
        BrowserPasswordSettingsPane(
            browser: browser,
            spaceAccess: spaceAccess,
            layout: .mobilePage,
            manage: { presentsPasswords = true }
        )
        .sheet(isPresented: $presentsPasswords) {
            MobilePasswordSettingsView(
                browser: browser,
                spaceAccess: spaceAccess
            )
        }
    }
}

#Preview("Mobile Credential Settings") {
    let fixture = MobileBrowserPreviewFixture()
    MobileCredentialSettingsView(
        browser: fixture.browser,
        spaceAccess: fixture.spaceAccess
    )
}
