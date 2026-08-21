import SwiftUI

/// The passwords this Space already holds for the site asking for one.
///
/// Everything the prompt needs from the page arrives through
/// `BrowserCredentialFillPort`, everything about how big it is comes from
/// `BrowserCredentialPromptMetrics`, and the surface under it is the one thing
/// a shell dresses differently. So both shells share this prompt rather than a
/// resemblance.
struct BrowserCredentialSuggestionPrompt: View {
    let request: BrowserCredentialFillRequest
    let port: BrowserCredentialFillPort
    let browser: BrowserStore
    let capabilities: BrowserInteractionCapabilities

    @State private var model = BrowserCredentialSuggestionModel()
    @State private var fillErrorMessage: String?

    var body: some View {
        BrowserCredentialPromptSurface(
            accessibilityLabel: Text("Crest password suggestions"),
            accessibilityIdentifier: "crest-password-suggestions",
            width: metrics.fillPromptWidth,
            metrics: metrics
        ) {
            BrowserCredentialSuggestionPromptContent(
                request: request,
                space: space,
                model: model,
                fillErrorMessage: fillErrorMessage,
                metrics: metrics,
                dismiss: port.dismiss,
                fill: fill
            )
        }
        .task(id: request.id) {
            fillErrorMessage = nil
            await model.load(request, in: port.spaceID, using: browser)
        }
        .onDisappear(perform: model.cancel)
    }

    private var metrics: BrowserCredentialPromptMetrics {
        BrowserCredentialPromptMetrics.resolve(capabilities)
    }

    private var space: BrowserSpace? {
        browser.session.space(id: port.spaceID)
    }

    private func fill(_ descriptor: CredentialDescriptor) {
        Task { @MainActor in
            do {
                guard
                    let credential = try await browser.credential(
                        id: descriptor.id,
                        in: port.spaceID
                    )
                else {
                    fillErrorMessage = "That password is no longer available."
                    return
                }
                try await port.fill(credential, request.id)
            } catch {
                fillErrorMessage = "The form changed before Crest could fill it."
            }
        }
    }
}
