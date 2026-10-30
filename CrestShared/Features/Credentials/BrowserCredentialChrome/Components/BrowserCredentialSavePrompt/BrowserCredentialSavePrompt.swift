import SwiftUI

/// The offer to keep the password a form was just submitted with.
///
/// Everything the prompt needs from the page arrives through
/// `BrowserCredentialSavePort`, every word it says comes from
/// `BrowserCredentialPromptRoute`, and everything about how it is drawn comes
/// from `BrowserCredentialPromptMetrics`. So both shells share this prompt
/// rather than a resemblance.
struct BrowserCredentialSavePrompt: View {
    let candidate: BrowserCredentialSaveCandidate
    let port: BrowserCredentialSavePort
    let browser: BrowserStore
    let metrics: BrowserCredentialPromptMetrics

    @State private var model = BrowserCredentialSavePromptModel()

    var body: some View {
        BrowserCredentialPromptSurface(
            accessibilityLabel: Text(route.title(spaceName: space?.name)),
            accessibilityIdentifier: "crest-password-save",
            width: metrics.savePromptWidth,
            metrics: metrics
        ) {
            BrowserCredentialSavePromptContent(
                candidate: candidate,
                route: route,
                destination: destination,
                space: space,
                namesSystemPasswordsDestination: namesSystemPasswordsDestination,
                metrics: metrics,
                dismiss: port.dismiss,
                switchDestination: switchDestination,
                perform: perform
            )
        }
        .task(id: candidate.id) {
            await prepare()
        }
    }

    private var space: BrowserSpaceIdentity? {
        browser.spaceModel(port.spaceID)?.identity
    }

    private var preferences: CredentialPreferences {
        browser.spaceModel(port.spaceID)?.settings.credentialPreferences ?? .seeded
    }

    /// Whether this prompt will go on to offer the password to the system's
    /// Passwords app after Crest has kept it.
    ///
    /// A shell that cannot make the offer never asks the policy: leaving the
    /// closure out of the port is the whole of that shell's answer.
    private var shouldOfferSystemPasswords: Bool {
        port.offerToSystemPasswords != nil && model.destination.keepsSpaceVault
            && browser.offersSystemPasswordWriteThrough(for: preferences)
    }

    private var route: BrowserCredentialPromptRoute {
        BrowserCredentialPromptRoute(
            phase: model.phase,
            systemPasswordOfferPhase: model.systemPasswordOfferPhase,
            offersSystemPasswords: shouldOfferSystemPasswords,
            destination: model.destination,
            offersDestinationChoice: model.offersDestinationChoice,
            appleNeverSaves: model.appleNeverSaves
        )
    }

    private var destination: BrowserCredentialPromptDestinationMetadata {
        route.destinationMetadata(
            spaceName: space?.name,
            syncsWithICloud: preferences.syncsCrestPasswordsWithICloud,
            presentation: metrics.destinationPresentation
        )
    }

    /// Whether the destination line already says iCloud in words, which is what
    /// lets it carry the cloud glyph instead of the Space's crest.
    private var namesSystemPasswordsDestination: Bool {
        !model.destination.keepsSpaceVault
            || (metrics.destinationPresentation == .combinedStatus
                && preferences.syncsCrestPasswordsWithICloud)
    }

    /// Sends this one save to the other place, when the core offers both.
    private var switchDestination: (() -> Void)? {
        guard let alternate = model.alternateDestination else { return nil }
        return {
            model.choose(alternate)
            if model.phase == .alreadyStored { port.dismiss() }
        }
    }

    private func perform(_ action: BrowserCredentialPromptPrimaryAction) {
        action.perform(self)
    }

    private func prepare() async {
        await model.prepare(
            candidate: candidate,
            in: port.spaceID,
            tab: port.tabID,
            browser: browser
        )
        guard !Task.isCancelled,
            port.presentedCandidateID() == candidate.id,
            model.phase == .alreadyStored
        else { return }
        port.dismiss()
    }

    private func offerToSystemPasswords() async {
        guard let offer = port.offerToSystemPasswords else { return }
        await model.offerToSystemPasswords {
            try await offer(
                candidate,
                "\(candidate.username) · \(space?.name ?? "this Space")"
            )
        }
    }
}

// MARK: - Actions - Primary action

extension BrowserCredentialSavePrompt: BrowserCredentialPromptPerformer {
    func save() {
        Task { @MainActor in
            await model.commit(
                candidate: candidate,
                in: port.spaceID,
                tab: port.tabID,
                browser: browser
            )
            guard port.presentedCandidateID() == candidate.id else { return }
            if case .sent = model.phase {
                port.dismiss()
                return
            }
            guard case .saved = model.phase else { return }
            guard shouldOfferSystemPasswords else {
                port.dismiss()
                return
            }
            await offerToSystemPasswords()
            guard model.systemPasswordOfferPhase == .completed else { return }
            port.dismiss()
        }
    }

    func retryPreparation() {
        Task { @MainActor in
            await prepare()
        }
    }

    func retrySystemPasswords() {
        Task { @MainActor in
            await offerToSystemPasswords()
            guard port.presentedCandidateID() == candidate.id,
                model.systemPasswordOfferPhase == .completed
            else { return }
            port.dismiss()
        }
    }
}
