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
    let metrics: BrowserCredentialPromptMetrics

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
                siteIconData: port.siteIconData,
                model: model,
                metrics: metrics,
                dismiss: port.dismiss,
                generateAndFill: generateAndFill
            )
        }
    }

    private var space: BrowserSpaceIdentity? {
        browser.spaceModel(port.spaceID)?.identity
    }

    private var spaceName: String {
        space?.name ?? "this Space"
    }

    private func generateAndFill() {
        Task { @MainActor in
            await model.generateSaveAndFill(
                generate: {
                    try BrowserStrongPasswordGenerator.generate(
                        from: browser.strongPasswordRecipe(for: request.requirements))
                },
                save: { password in
                    // Saved under what the form's username field holds now, so
                    // sending the form finds the password already kept. With no
                    // username yet, it waits for the form to be sent, which
                    // offers to save it under the name the form sends.
                    let username = await port.formUsername(request.id) ?? request.usernameHint ?? ""
                    guard !username.isEmpty else { return }
                    let candidate = BrowserCredentialSaveCandidate(
                        id: UUID(),
                        origin: request.origin,
                        topLevelOrigin: request.topLevelOrigin,
                        username: username,
                        password: password,
                        passwordKind: .new,
                        isCrossOriginFrame: request.isCrossOriginFrame,
                        submittedAt: .now
                    )
                    _ = try await browser.commitCredentialSave(
                        candidate,
                        in: port.spaceID
                    )
                },
                fill: { password in
                    try await port.fillGeneratedPassword(password, request.id)
                }
            )
        }
    }
}
