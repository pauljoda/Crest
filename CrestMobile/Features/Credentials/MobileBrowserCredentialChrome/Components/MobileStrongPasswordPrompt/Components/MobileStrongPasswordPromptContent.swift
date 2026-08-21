import SwiftUI

struct MobileStrongPasswordPromptContent: View {
    let request: BrowserCredentialFillRequest
    let space: BrowserSpace?
    let model: BrowserStrongPasswordOperationModel
    let dismiss: () -> Void
    let generateAndFill: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            BrowserCredentialPromptHeader(
                kind: .strongPassword,
                request: request,
                space: space,
                dismiss: dismiss
            )
            if request.isCrossOriginFrame {
                BrowserCredentialCrossOriginNotice(
                    message: "Embedded password form from \(request.topLevelOrigin.description)"
                )
            }
            MobileStrongPasswordExplanation(
                spaceName: space?.name ?? "this Space"
            )
            MobileStrongPasswordActionButton(
                isWorking: model.isWorking,
                tint: space?.accent.color ?? .accentColor,
                action: generateAndFill
            )
            if model.hasFailed {
                BrowserCredentialPromptError(
                    "The form changed before Crest could fill the password."
                )
            }
        }
    }
}
