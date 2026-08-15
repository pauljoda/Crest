import SwiftUI

struct MobilePasswordSystemPasskeysSection: View {
    let access: BrowserPasskeyAccessController

    var body: some View {
        Section("System passkeys") {
            BrowserPasskeyAccessView(access: access)
        }
    }
}

#Preview {
    let fixture = MobileBrowserPreviewFixture()
    Form {
        MobilePasswordSystemPasskeysSection(access: fixture.passkeyAccess)
    }
}
