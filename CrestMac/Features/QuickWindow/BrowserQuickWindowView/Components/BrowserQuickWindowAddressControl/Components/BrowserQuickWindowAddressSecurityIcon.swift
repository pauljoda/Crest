import SwiftUI

/// The lock before a secure page's address; nothing for any other.
struct BrowserQuickWindowAddressSecurityIcon: View {
    let isSecure: Bool

    var body: some View {
        if isSecure {
            Image(systemName: "lock.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }
}

#if DEBUG
    #Preview("Secure and insecure") {
        HStack {
            BrowserQuickWindowAddressSecurityIcon(isSecure: true)
            BrowserQuickWindowAddressSecurityIcon(isSecure: false)
        }.padding()
    }
#endif
