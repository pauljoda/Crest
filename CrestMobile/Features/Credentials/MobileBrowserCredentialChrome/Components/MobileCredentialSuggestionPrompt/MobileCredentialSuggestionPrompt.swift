import SwiftUI

struct MobileCredentialSuggestionPrompt: View {
    let request: BrowserCredentialFillRequest
    let page: MobileBrowserPage
    let browser: BrowserStore

    @State private var model = BrowserCredentialSuggestionModel()
    @State private var fillErrorMessage: String?

    var body: some View {
        MobileCredentialPromptSurface(
            accessibilityLabel: "Crest password suggestions",
            accessibilityIdentifier: "crest-password-suggestions"
        ) {
            MobileCredentialSuggestionPromptContent(
                request: request,
                space: space,
                model: model,
                fillErrorMessage: fillErrorMessage,
                dismiss: page.dismissCredentialFillRequest,
                fill: fill
            )
        }
        .task(id: request.id) {
            fillErrorMessage = nil
            await model.load(request, in: page.spaceID, using: browser)
        }
        .onDisappear(perform: model.cancel)
    }

    private var space: BrowserSpace? {
        browser.session.space(id: page.spaceID)
    }

    private func fill(_ descriptor: CredentialDescriptor) {
        Task { @MainActor in
            do {
                guard
                    let credential = try await browser.credential(
                        id: descriptor.id,
                        in: page.spaceID
                    )
                else {
                    fillErrorMessage = "That password is no longer available."
                    return
                }
                try await page.fillCredential(credential, for: request.id)
            } catch {
                fillErrorMessage =
                    "The form changed before Crest could fill it."
            }
        }
    }
}

#Preview("Credential Suggestions Prompt") {
    let fixture = MobileBrowserCredentialChromePreviewFixture()

    MobileCredentialSuggestionPrompt(
        request: fixture.currentPasswordRequest,
        page: fixture.page,
        browser: fixture.browser
    )
    .frame(width: 390)
}
