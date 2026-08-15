import SwiftUI

struct BrowserPeekInitialLoadingSurface: View {
    var body: some View {
        Rectangle()
            .fill(.regularMaterial)
            .overlay {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Loading Peek")
            }
            .allowsHitTesting(false)
            .transition(.opacity)
    }
}

#Preview {
    BrowserPeekInitialLoadingSurface()
        .frame(width: 640, height: 420)
}
