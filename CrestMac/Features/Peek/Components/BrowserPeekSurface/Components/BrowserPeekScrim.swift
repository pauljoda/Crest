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

#Preview {
    BrowserPeekScrim(opacity: 0.34, dismiss: {})
        .frame(width: 900, height: 620)
}
