import SwiftUI

struct BrowserCredentialSuggestionPromptContent: View {
    let request: BrowserCredentialFillRequest
    let space: BrowserSpaceIdentity?
    let siteIconData: Data?
    let model: BrowserCredentialSuggestionModel
    let fillErrorMessage: String?
    let metrics: BrowserCredentialPromptMetrics
    let dismiss: () -> Void
    let fill: (BrowserCredentialSuggestion) -> Void
    let fillCode: (BrowserOneTimeCodeSuggestion) -> Void
    let beginPairing: () -> Void
    let openPasswordsApp: () -> Void
    let submitPairingCode: (String) -> Void

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: BrowserCredentialPromptMetrics.contentSpacing
        ) {
            BrowserCredentialPromptHeader(
                kind: request.isOneTimeCodeField ? .oneTimeCodes : .suggestions,
                request: request,
                space: space,
                siteIconData: siteIconData,
                metrics: metrics,
                dismiss: dismiss
            )
            if request.isCrossOriginFrame {
                BrowserCredentialCrossOriginNotice(
                    message: "Embedded sign-in from \(request.topLevelOrigin.description)"
                )
            }
            if let pairingStep = model.pairingStep {
                BrowserCredentialPairingCodeEntry(
                    step: pairingStep,
                    feedback: model.pairingFeedback,
                    submit: submitPairingCode,
                    cancel: model.cancelPairing
                )
            } else {
                BrowserCredentialSuggestionState(
                    isLoading: model.isLoading,
                    suggestions: model.suggestions,
                    codes: model.codes,
                    offersPairing: model.offersPairing,
                    offersOpeningPasswordsApp: model.offersOpeningPasswordsApp,
                    metrics: metrics,
                    fill: fill,
                    fillCode: fillCode,
                    beginPairing: beginPairing,
                    openPasswordsApp: openPasswordsApp
                )
                if let message = model.pairingFeedback?.message {
                    BrowserCredentialPromptError(verbatim: String(localized: message))
                }
            }
            if model.hasFailed {
                BrowserCredentialPromptError(
                    "Crest couldn’t read this Space’s passwords."
                )
            }
            if let fillErrorMessage {
                BrowserCredentialPromptError(verbatim: fillErrorMessage)
            }
        }
    }
}
