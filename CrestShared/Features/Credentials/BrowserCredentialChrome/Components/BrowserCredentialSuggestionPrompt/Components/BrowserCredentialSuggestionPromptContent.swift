import SwiftUI

/// The fill popup's rows: the logins, with the selected one marked, and a way
/// into the Space's passwords at the foot. A band keeps its header naming the
/// Space and the site; a panel under the field names them on each row.
struct BrowserCredentialSuggestionPromptContent: View {
    let request: BrowserCredentialFillRequest
    let space: BrowserSpaceIdentity?
    let siteIconData: Data?
    let model: BrowserCredentialSuggestionModel
    let fillErrorMessage: String?
    let metrics: BrowserCredentialPromptMetrics
    let dismiss: () -> Void
    let openPasswords: (() -> Void)?
    let fill: (CredentialDescriptor) -> Void

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: BrowserCredentialPromptMetrics.contentSpacing
        ) {
            if metrics.showsSuggestionHeader {
                BrowserCredentialPromptHeader(
                    kind: .suggestions,
                    request: request,
                    space: space,
                    siteIconData: siteIconData,
                    metrics: metrics,
                    dismiss: dismiss
                )
            }
            if request.isCrossOriginFrame {
                BrowserCredentialCrossOriginNotice(
                    message: "Embedded sign-in from \(request.topLevelOrigin.description)"
                )
            }
            BrowserCredentialSuggestionState(
                isLoading: model.isLoading,
                suggestions: model.suggestions,
                selectedID: model.selectedSuggestion?.id,
                context: context,
                metrics: metrics,
                fill: fill
            )
            if model.hasFailed {
                BrowserCredentialPromptError(
                    "Crest couldn’t read this Space’s passwords."
                )
            }
            if let fillErrorMessage {
                BrowserCredentialPromptError(verbatim: fillErrorMessage)
            }
            if let openPasswords, !metrics.showsSuggestionHeader {
                BrowserCredentialPopupFooter(
                    title: "Passwords…",
                    metrics: metrics,
                    open: openPasswords
                )
            }
        }
    }

    private var context: BrowserCredentialSuggestionContext {
        BrowserCredentialSuggestionContext(
            iconData: request.isCrossOriginFrame ? nil : siteIconData,
            source: [space?.name, request.origin.host].compactMap(\.self).joined(separator: " · "),
            fillsUsernameOnly: request.fields.username != nil && request.fields.password == nil
        )
    }
}
