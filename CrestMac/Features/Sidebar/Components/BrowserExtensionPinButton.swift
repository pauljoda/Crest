import SwiftUI

struct BrowserExtensionPinButton: View {
    let isPinned: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isPinned ? "pin.slash.fill" : "pin.fill")
                .font(.system(size: 8, weight: .semibold))
                .frame(
                    width: BrowserPinnedExtensionStripLayoutPolicy.pinControlSize,
                    height: BrowserPinnedExtensionStripLayoutPolicy.pinControlSize
                )
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .background(.regularMaterial, in: .circle)
        .accessibilityLabel(isPinned ? "Unpin Extension" : "Pin Extension")
        .help(isPinned ? "Unpin Extension" : "Pin Extension")
    }
}
