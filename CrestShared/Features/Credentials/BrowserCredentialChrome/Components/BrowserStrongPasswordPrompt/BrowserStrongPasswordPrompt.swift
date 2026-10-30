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
    /// Whether the generated password went to Apple Passwords instead of the Space.
    @State private var sentToApplePasswords = false
    /// Whether Apple has been asked about the site and will take the password.
    /// Until it has answered, the prompt names the Space and never Apple.
    @State private var appleWillTakePassword = false

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
                destinationName: destinationName,
                sentToApplePasswords: sentToApplePasswords,
                metrics: metrics,
                dismiss: port.dismiss,
                generateAndFill: generateAndFill
            )
        }
        .task(id: request.id) {
            appleWillTakePassword = false
            appleWillTakePassword =
                await browser.applePasswordsSaveAnswer(for: candidate(for: ""), in: port.spaceID, tab: port.tabID)
                .support != nil
        }
    }

    private var space: BrowserSpaceIdentity? {
        browser.spaceModel(port.spaceID)?.identity
    }

    /// Where the generated password is kept before it is filled: Apple
    /// Passwords where the Space saves there, otherwise the Space itself.
    private var destinationName: String {
        appleWillTakePassword ? "Apple Passwords" : spaceName
    }

    private func candidate(for password: String) -> BrowserCredentialSaveCandidate {
        BrowserCredentialSaveCandidate(
            id: UUID(),
            origin: request.origin,
            topLevelOrigin: request.topLevelOrigin,
            username: request.usernameHint ?? "",
            password: password,
            passwordKind: .new,
            isCrossOriginFrame: request.isCrossOriginFrame,
            submittedAt: request.requestedAt
        )
    }

    private var spaceName: String {
        space?.name ?? "this Space"
    }

    private func generateAndFill() {
        Task { @MainActor in
            await model.generateSaveAndFill(
                generate: { try BrowserStrongPasswordGenerator.generate(from: browser.strongPasswordRecipe()) },
                save: { password in
                    let candidate = candidate(for: password)
                    // Apple Passwords gets the password first and confirms in its own
                    // alert. If it cannot take it, the Space keeps it, so it is never lost.
                    sentToApplePasswords = try await browser.keepGeneratedPassword(
                        candidate, in: port.spaceID, tab: port.tabID)
                    if sentToApplePasswords {
                        port.rememberPresavedPassword(
                            BrowserCredentialPresavedPassword(
                                origin: request.origin, topLevelOrigin: request.topLevelOrigin,
                                password: password, username: candidate.username))
                    }
                },
                fill: { password in
                    try await port.fillGeneratedPassword(password, request.id)
                }
            )
        }
    }
}
