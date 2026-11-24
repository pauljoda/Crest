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
    let metrics: BrowserCredentialPromptMetrics

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
                siteIconData: port.siteIconData,
                model: model,
                fillErrorMessage: fillErrorMessage,
                metrics: metrics,
                dismiss: port.dismiss,
                openPasswords: port.openPasswords,
                fill: fill
            )
        }
        .task(id: request.id) {
            fillErrorMessage = nil
            await model.load(request, in: port.spaceID, using: browser)
            // Return and the arrows go to the popup only once it has a row
            // to take; otherwise Return sends the form.
            if !Task.isCancelled, !model.suggestions.isEmpty {
                port.holdKeys(true, request.id)
            }
        }
        .onChange(of: port.keyPress) { _, press in
            press.map { answer($0.key) }
        }
        .onDisappear {
            port.holdKeys(false, request.id)
            model.cancel()
        }
    }

    /// What a key the page held back does: the arrows move the selection,
    /// Return fills it, Escape closes the popup.
    private func answer(_ key: BrowserCredentialPopupKey) {
        if key.dismissesPopup {
            port.dismiss()
        } else if key.choosesSelection {
            if let selected = model.selectedSuggestion { fill(selected) } else { port.dismiss() }
        } else {
            model.moveSelection(by: key.step)
        }
    }

    private var space: BrowserSpaceIdentity? {
        browser.spaceModel(port.spaceID)?.identity
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
