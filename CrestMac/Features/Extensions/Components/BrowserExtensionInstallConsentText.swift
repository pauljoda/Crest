import SwiftUI

struct BrowserExtensionInstallConsentText: View {
    var body: some View {
        Text(
            "Adding this extension allows the permissions and website access listed here in this Space. Optional access is requested separately. You can change access later in Extensions settings. Replacing an installed extension keeps your existing choices."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
}
