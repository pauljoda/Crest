import SwiftUI

struct BrowserStrongPasswordPromptContent: View {
    let request: BrowserCredentialFillRequest
    let space: BrowserSpace?
    let siteIconData: Data?
    let model: BrowserStrongPasswordOperationModel
    let metrics: BrowserCredentialPromptMetrics
    let dismiss: () -> Void
    let generateAndFill: () -> Void

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: BrowserCredentialPromptMetrics.strongPasswordContentSpacing
        ) {
            BrowserCredentialPromptHeader(
                kind: .strongPassword,
                request: request,
                space: space,
                siteIconData: siteIconData,
                metrics: metrics,
                dismiss: dismiss
            )
            if request.isCrossOriginFrame {
                BrowserCredentialCrossOriginNotice(
                    message: "Embedded password form from \(request.topLevelOrigin.description)"
                )
            }
            BrowserStrongPasswordExplanation(
                spaceName: space?.name ?? "this Space"
            )
            BrowserStrongPasswordActionButton(
                isWorking: model.isWorking,
                tint: space?.accent.color ?? .accentColor,
                metrics: metrics,
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
