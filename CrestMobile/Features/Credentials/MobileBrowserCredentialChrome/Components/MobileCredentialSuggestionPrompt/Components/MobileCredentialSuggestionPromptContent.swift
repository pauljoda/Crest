import SwiftUI

struct MobileCredentialSuggestionPromptContent: View {
    let request: BrowserCredentialFillRequest
    let space: BrowserSpace?
    let model: BrowserCredentialSuggestionModel
    let fillErrorMessage: String?
    let dismiss: () -> Void
    let fill: (CredentialDescriptor) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MobileCredentialPromptHeader(
                kind: .suggestions,
                request: request,
                space: space,
                dismiss: dismiss
            )
            if request.isCrossOriginFrame {
                MobileCredentialCrossOriginNotice(
                    message: "Embedded sign-in from \(request.topLevelOrigin.description)"
                )
            }
            MobileCredentialSuggestionState(
                isLoading: model.isLoading,
                suggestions: model.suggestions,
                fill: fill
            )
            MobileCredentialSuggestionFeedback(
                hasLoadFailed: model.hasFailed,
                fillErrorMessage: fillErrorMessage
            )
        }
    }
}
