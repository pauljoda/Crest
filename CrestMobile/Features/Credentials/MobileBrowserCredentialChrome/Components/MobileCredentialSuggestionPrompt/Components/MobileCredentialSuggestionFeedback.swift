import SwiftUI

struct MobileCredentialSuggestionFeedback: View {
    let hasLoadFailed: Bool
    let fillErrorMessage: String?

    var body: some View {
        Group {
            if hasLoadFailed {
                MobileCredentialPromptError(
                    "Crest couldn’t read this Space’s passwords."
                )
            }
            if let fillErrorMessage {
                MobileCredentialPromptError(verbatim: fillErrorMessage)
            }
        }
    }
}

#Preview("Credential Suggestion Feedback") {
    MobileCredentialSuggestionFeedback(
        hasLoadFailed: false,
        fillErrorMessage: "The form changed before Crest could fill it."
    )
    .padding()
}
