import SwiftUI

struct MobileCredentialSuggestionState: View {
    let isLoading: Bool
    let suggestions: [CredentialDescriptor]
    let fill: (CredentialDescriptor) -> Void

    @ViewBuilder
    var body: some View {
        if isLoading {
            ProgressView("Checking this Space…")
                .controlSize(.small)
                .frame(minHeight: 44)
        } else if suggestions.isEmpty {
            Text("No Crest passwords are saved for this site in this Space.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(minHeight: 44, alignment: .leading)
        } else {
            MobileCredentialSuggestionList(
                suggestions: suggestions,
                fill: fill
            )
        }
    }
}
