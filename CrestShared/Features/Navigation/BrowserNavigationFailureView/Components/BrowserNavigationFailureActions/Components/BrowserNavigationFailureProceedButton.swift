import SwiftUI

struct BrowserNavigationFailureProceedButton: View {
    let action: () -> Void

    var body: some View {
        Button("Proceed Anyway", role: .destructive, action: action)
            .buttonStyle(.crestDestructive)
            .accessibilityHint(
                "Trusts this exact site certificate for the current browsing session"
            )
    }
}

#if DEBUG
    #Preview("Component") {
        BrowserNavigationFailureProceedButton(action: {}).padding()
    }
#endif
