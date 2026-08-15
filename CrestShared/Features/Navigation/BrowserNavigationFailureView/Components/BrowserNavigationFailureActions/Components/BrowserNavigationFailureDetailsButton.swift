import SwiftUI

struct BrowserNavigationFailureDetailsButton: View {
    let showsDetails: Bool
    let action: () -> Void

    private var title: LocalizedStringResource {
        showsDetails ? "Hide Details" : "Details"
    }

    var body: some View {
        Button(action: action) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: showsDetails ? "chevron.up" : "info.circle")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .accessibilityIdentifier("navigation-failure-details")
    }
}

#Preview("Navigation Failure Details Button") {
    BrowserNavigationFailureDetailsButton(
        showsDetails: false,
        action: {}
    )
    .padding()
}
