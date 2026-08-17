import SwiftUI

struct MobileCredentialSuggestionList: View {
    let suggestions: [CredentialDescriptor]
    let fill: (CredentialDescriptor) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(suggestions) { suggestion in
                    MobileCredentialSuggestionRow(
                        suggestion: suggestion,
                        fill: { fill(suggestion) }
                    )
                }
            }
        }
        .frame(maxHeight: 176)
    }
}
