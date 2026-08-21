import SwiftUI

struct MobileStrongPasswordPrompt: View {
    let request: BrowserCredentialFillRequest
    let page: MobileBrowserPage
    let browser: BrowserStore
    let capabilities: BrowserInteractionCapabilities

    @State private var model = BrowserStrongPasswordOperationModel()

    var body: some View {
        BrowserCredentialPromptSurface(
            accessibilityLabel: Text("Strong password for \(spaceName)"),
            accessibilityIdentifier: "crest-strong-password",
            width: metrics.fillPromptWidth,
            metrics: metrics
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

    private var metrics: BrowserCredentialPromptMetrics {
        BrowserCredentialPromptMetrics.resolve(capabilities)
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
