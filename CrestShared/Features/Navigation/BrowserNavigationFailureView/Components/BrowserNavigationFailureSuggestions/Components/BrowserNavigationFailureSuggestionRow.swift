import SwiftUI

struct BrowserNavigationFailureSuggestionRow: View {
    let suggestion: LocalizedStringResource
    let accent: Color

    var body: some View {
        Label {
            Text(suggestion)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(accent)
                .accessibilityHidden(true)
        }
        .font(.callout)
    }
}

#Preview("Navigation Failure Suggestion Row") {
    BrowserNavigationFailureSuggestionRow(
        suggestion: "Check the address for typing mistakes.",
        accent: .blue
    )
    .padding()
}
