import SwiftUI

struct BrowserPeekScrim: View {
    let opacity: Double
    let dismiss: () -> Void

    var body: some View {
        Button(action: dismiss) {
            Color.black.opacity(opacity)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHidden(true)
    }
}
