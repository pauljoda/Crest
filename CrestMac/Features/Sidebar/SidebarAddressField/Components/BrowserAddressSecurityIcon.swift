import SwiftUI

struct BrowserAddressSecurityIcon: View {
    let isSecure: Bool

    var body: some View {
        Image(systemName: isSecure ? "lock.fill" : "lock.open.fill")
            .font(
                .system(
                    size: BrowserTabTrailingControlPolicy.glyphSize,
                    weight: .medium
                )
            )
            .frame(
                width: BrowserAddressSecurityControlPolicy.controlSize,
                height: BrowserAddressSecurityControlPolicy.controlSize
            )
            .contentShape(.rect)
    }
}

#Preview {
    BrowserAddressSecurityIcon(isSecure: false)
        .padding()
}
