import SwiftUI

struct BrowserAddressPlaceholderGlyph: View {
    let isSecure: Bool

    var body: some View {
        Image(systemName: isSecure ? "lock.fill" : "magnifyingglass")
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .frame(
                width: BrowserAddressSecurityControlPolicy.controlSize,
                height: BrowserAddressSecurityControlPolicy.controlSize
            )
            .accessibilityHidden(true)
    }
}

#Preview {
    BrowserAddressPlaceholderGlyph(isSecure: true)
        .padding()
}
