import SwiftUI

// MARK: - Types

/// One password the prompt offers: its style, the recipe it was drawn from,
/// and the password itself, which stays in the prompt until it is filled or
/// the prompt closes.
struct BrowserStrongPasswordOffer: Equatable {
    let style: PasswordStyle
    let recipe: StrongPasswordRecipe
    let password: String
}

/// The offer to make a password for the form asking for a new one.
///
/// The password is drawn as the offer opens, so the person sees what Crest
/// will fill and can draw another. Where the site allows it, a random password
/// with symbols is offered beside Crest's grouped one. Everything the prompt
/// needs from the page arrives through `BrowserCredentialFillPort`, and
/// everything about how big it is comes from `BrowserCredentialPromptMetrics`,
/// so both shells share this prompt rather than a resemblance.
struct BrowserStrongPasswordPrompt: View {
    let request: BrowserCredentialFillRequest
    let port: BrowserCredentialFillPort
    let browser: BrowserStore
    let metrics: BrowserCredentialPromptMetrics

    @State private var model = BrowserStrongPasswordOperationModel()
    @State private var offers: [BrowserStrongPasswordOffer] = []
    @State private var selectedIndex = 0

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
                offers: offers,
                selectedIndex: selectedIndex,
                metrics: metrics,
                dismiss: port.dismiss,
                openPasswords: port.openPasswords,
                redraw: redraw,
                choose: choose
            )
        }
        .task(id: request.id) {
            port.holdKeys(true, request.id)
            selectedIndex = 0
            let primary = draw(.grouped)
            let alternative = primary?.recipe.hasRandomAlternative == true ? draw(.random) : nil
            offers = [primary, alternative].compactMap(\.self)
        }
        .onChange(of: port.keyPress) { _, press in
            press.map { answer($0.key) }
        }
        .onDisappear {
            port.holdKeys(false, request.id)
        }
    }

    private var space: BrowserSpaceIdentity? {
        browser.spaceModel(port.spaceID)?.identity
    }

    private var spaceName: String {
        space?.name ?? "this Space"
    }

    /// A password in `style` for this field, or nil where the site's rules
    /// leave nothing to draw.
    private func draw(_ style: PasswordStyle) -> BrowserStrongPasswordOffer? {
        guard let recipe = try? browser.strongPasswordRecipe(for: request.requirements, style: style),
            let password = try? BrowserStrongPasswordGenerator.generate(from: recipe)
        else { return nil }
        return BrowserStrongPasswordOffer(style: style, recipe: recipe, password: password)
    }

    /// Draws another password for the offer at `index`.
    private func redraw(_ index: Int) {
        guard offers.indices.contains(index), let offer = draw(offers[index].style) else { return }
        offers[index] = offer
    }

    /// What a key the page held back does: the arrows move between the
    /// offers, Return takes the selected one, Escape closes the prompt.
    private func answer(_ key: BrowserCredentialPopupKey) {
        if key.dismissesPopup {
            port.dismiss()
        } else if key.choosesSelection {
            choose(selectedIndex)
        } else if !offers.isEmpty {
            selectedIndex = min(max(selectedIndex + key.step, 0), offers.count - 1)
        }
    }

    private func choose(_ index: Int) {
        guard offers.indices.contains(index) else { return }
        let password = offers[index].password
        Task { @MainActor in
            await model.generateSaveAndFill(
                generate: { password },
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
