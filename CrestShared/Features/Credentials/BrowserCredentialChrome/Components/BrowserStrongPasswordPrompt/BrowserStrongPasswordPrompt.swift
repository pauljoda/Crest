import SwiftUI

/// The offer to invent a password for the form asking for a new one.
///
/// Everything the prompt needs from the page arrives through
/// `BrowserCredentialFillPort`, everything about how big it is comes from
/// `BrowserCredentialPromptMetrics`, and the surface under it is the one thing
/// a shell dresses differently. So both shells share this prompt rather than a
/// resemblance.
struct BrowserStrongPasswordPrompt: View {
    let request: BrowserCredentialFillRequest
    let port: BrowserCredentialFillPort
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
            BrowserStrongPasswordPromptContent(
                request: request,
                space: space,
                model: model,
                metrics: metrics,
                dismiss: port.dismiss,
                generateAndFill: generateAndFill
            )
        }
    }

    private var metrics: BrowserCredentialPromptMetrics {
        BrowserCredentialPromptMetrics.resolve(capabilities)
    }

    private var space: BrowserSpace? {
        browser.session.space(id: port.spaceID)
    }

    private var spaceName: String {
        space?.name ?? "this Space"
    }

    private func generateAndFill() {
        Task { @MainActor in
            await model.generateAndFill { password in
                try await port.fillGeneratedPassword(password, request.id)
            }
        }
    }
}
