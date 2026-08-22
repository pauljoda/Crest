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
                perform: perform
            )
        }
        .task(id: candidate.id) {
            await prepare()
        }
    }

    private var space: BrowserSpace? {
        browser.session.space(id: port.spaceID)
    }

    private var preferences: BrowserCredentialPreferences {
        space?.credentialPreferences ?? .default
    }

    /// Whether this prompt will go on to offer the password to the system's
    /// Passwords app after Crest has kept it.
    ///
    /// A shell that cannot make the offer never asks the policy: leaving the
    /// closure out of the port is the whole of that shell's answer.
    private var shouldOfferSystemPasswords: Bool {
        port.offerToSystemPasswords != nil
            && BrowserSystemPasswordWriteThroughPolicy.shouldOffer(
                preferences: preferences,
                availability:
                    BrowserSystemPasswordWriteThroughSystem.launchAvailability,
                isPrivateBrowsing: browser.isPrivateBrowsing
            )
    }

    private var route: BrowserCredentialPromptRoute {
        BrowserCredentialPromptRoute(
            phase: model.phase,
            systemPasswordOfferPhase: model.systemPasswordOfferPhase,
            offersSystemPasswords: shouldOfferSystemPasswords
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
        metrics.destinationPresentation == .combinedStatus
            && preferences.syncsCrestPasswordsWithICloud
    }

    private func perform(_ action: BrowserCredentialPromptPrimaryAction) {
        switch action {
        case .commit:
            save()
        case .retryCredentialPreparation:
            retry()
        case .retrySystemPasswords:
            retrySystemPasswords()
        }
    }

    private func prepare() async {
        await model.prepare(
            candidate: candidate,
            in: port.spaceID,
            browser: browser
        )
        guard !Task.isCancelled,
            port.presentedCandidateID() == candidate.id,
            model.phase == .alreadyStored
        else { return }
        port.dismiss()
    }

    private func retry() {
        Task { @MainActor in
            await prepare()
        }
    }

    private func save() {
        Task { @MainActor in
            await model.commit(
                candidate: candidate,
                in: port.spaceID,
                browser: browser
            )
            guard port.presentedCandidateID() == candidate.id,
                case .saved = model.phase
            else { return }
            guard shouldOfferSystemPasswords else {
                port.dismiss()
                return
            }
            await offerToSystemPasswords()
            guard model.systemPasswordOfferPhase == .completed else { return }
            port.dismiss()
        }
    }

    private func retrySystemPasswords() {
        Task { @MainActor in
            await offerToSystemPasswords()
            guard port.presentedCandidateID() == candidate.id,
                model.systemPasswordOfferPhase == .completed
            else { return }
            port.dismiss()
        }
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
