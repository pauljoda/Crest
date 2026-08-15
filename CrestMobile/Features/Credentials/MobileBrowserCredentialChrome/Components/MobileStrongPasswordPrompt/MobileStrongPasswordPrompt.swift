import SwiftUI

struct MobileStrongPasswordPrompt: View {
    let request: BrowserCredentialFillRequest
    let page: MobileBrowserPage
    let browser: BrowserStore

    @State private var model = BrowserStrongPasswordOperationModel()

    var body: some View {
        MobileCredentialPromptSurface(
            accessibilityLabel: "Strong password for \(spaceName)",
            accessibilityIdentifier: "crest-strong-password"
        ) {
            MobileStrongPasswordPromptContent(
                request: request,
                space: space,
                model: model,
                dismiss: page.dismissCredentialFillRequest,
                generateAndFill: generateAndFill
            )
        }
    }

    private var space: BrowserSpace? {
        browser.session.space(id: page.spaceID)
    }

    private var spaceName: String {
        space?.name ?? "this Space"
    }

    private func generateAndFill() {
        Task { @MainActor in
            await model.generateAndFill { password in
                try await page.fillGeneratedPassword(password, for: request.id)
            }
        }
    }
}

#Preview("Strong Password Prompt") {
    let fixture = MobileBrowserCredentialChromePreviewFixture()

    MobileStrongPasswordPrompt(
        request: fixture.newPasswordRequest,
        page: fixture.page,
        browser: fixture.browser
    )
    .frame(width: 390)
}
