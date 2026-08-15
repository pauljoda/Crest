import SwiftUI

struct BrowserNavigationFailureProceedButton: View {
    let action: () -> Void

    var body: some View {
        Button("Proceed Anyway", role: .destructive, action: action)
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityHint(
                "Trusts this exact site certificate for the current browsing session"
            )
    }
}

#Preview("Navigation Failure Proceed Button") {
    BrowserNavigationFailureProceedButton(action: {})
        .padding()
}
