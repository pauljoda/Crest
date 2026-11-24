import SwiftUI

/// The passwords the prompt offers, as rows the arrow keys move between: Crest's
/// own, with what the site asked for, and where the site allows it, a random
/// one with symbols. A band keeps its header naming the Space and the site.
struct BrowserStrongPasswordPromptContent: View {
    let request: BrowserCredentialFillRequest
    let space: BrowserSpaceIdentity?
    let siteIconData: Data?
    let model: BrowserStrongPasswordOperationModel
    let offers: [BrowserStrongPasswordOffer]
    let selectedIndex: Int
    let metrics: BrowserCredentialPromptMetrics
    let dismiss: () -> Void
    let openPasswords: (() -> Void)?
    let redraw: (Int) -> Void
    let choose: (Int) -> Void

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: BrowserCredentialPromptMetrics.contentSpacing
        ) {
            if metrics.showsSuggestionHeader {
                BrowserCredentialPromptHeader(
                    kind: .strongPassword,
                    request: request,
                    space: space,
                    siteIconData: siteIconData,
                    metrics: metrics,
                    dismiss: dismiss
                )
            }
            if request.isCrossOriginFrame {
                BrowserCredentialCrossOriginNotice(
                    message: "Embedded password form from \(request.topLevelOrigin.description)"
                )
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(offers.enumerated()), id: \.offset) { index, offer in
                    BrowserStrongPasswordOfferRow(
                        offer: offer,
                        title: index == 0 ? "Use Strong Password" : "Random with Symbols",
                        isSelected: index == selectedIndex,
                        isWorking: model.isWorking,
                        metrics: metrics,
                        redraw: { redraw(index) },
                        choose: { choose(index) }
                    )
                }
            }
            .padding(.horizontal, -metrics.suggestionRowHighlightBleed)
            if offers.isEmpty {
                BrowserCredentialPromptError(
                    "This site’s rules leave no password Crest can make."
                )
            }
            if model.phase == .failedBeforeSave {
                BrowserCredentialPromptError(
                    "Crest couldn’t save a strong password. Nothing was filled."
                )
            } else if model.phase == .savedButFillFailed {
                BrowserCredentialPromptError(
                    "The password is saved in this Space, but the form changed before Crest could fill it."
                )
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
}
