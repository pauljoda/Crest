import SwiftUI

struct BrowserExtensionInstallConsentText: View {
    var body: some View {
        Text(
            "Choose the permissions and website access to allow in this Space. Uncheck any access you want to block. Some features may not work without it. Optional access is requested separately, and you can change your choices later in Extensions settings. Replacing an extension keeps existing choices unless you change them here."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
}
