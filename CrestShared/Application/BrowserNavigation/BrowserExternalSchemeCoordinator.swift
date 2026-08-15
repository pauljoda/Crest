import Foundation

/// Hands an external-scheme navigation to the operating system, after consent.
/// Platform-neutral: the page that owns it supplies both the prompt and the one
/// call that actually opens a URL.
@MainActor
final class BrowserExternalSchemeCoordinator {
    typealias Prompt =
        @MainActor (
            BrowserSiteOrigin,
            URL,
            String
        ) async -> BrowserExternalSchemePromptResponse

    private let spaceID: SpaceID
    private let spaceName: String
    private let permissionCenter: BrowserSitePermissionCenter
    private let prompt: Prompt
    private let opensExternalURL: (URL) -> Void

    init(
        spaceID: SpaceID,
        spaceName: String,
        permissionCenter: BrowserSitePermissionCenter,
        prompt: @escaping Prompt,
        opensExternalURL: @escaping (URL) -> Void
    ) {
        self.spaceID = spaceID
        self.spaceName = spaceName
        self.permissionCenter = permissionCenter
        self.prompt = prompt
        self.opensExternalURL = opensExternalURL
    }

    /// Starts the hand-off. WebKit cannot wait for a prompt, so the caller has
    /// already cancelled the navigation and this returns immediately.
    func handOff(
        destinationURL: URL,
        trigger: BrowserPopupTrigger,
        origin: BrowserSiteOrigin?
    ) {
        Task { [weak self] in
            await self?.resolve(
                destinationURL: destinationURL,
                trigger: trigger,
                origin: origin
            )
        }
    }

    /// The hand-off itself, awaited. Split out so the consent rules can be
    /// exercised without a live prompt.
    func resolve(
        destinationURL: URL,
        trigger: BrowserPopupTrigger,
        origin: BrowserSiteOrigin?
    ) async {
        // Without an origin there is nothing to attribute or remember a choice
        // against, so the safe answer is to do nothing at all.
        guard let origin,
            let scheme = destinationURL.scheme?.lowercased(),
            !scheme.isEmpty
        else { return }

        switch BrowserExternalSchemeConsent.resolve(
            trigger: trigger,
            decision: permissionCenter.decision(
                for: .externalApplications,
                origin: origin,
                detail: scheme,
                in: spaceID
            )
        ) {
        case .open:
            opensExternalURL(destinationURL)
        case .block:
            return
        case .prompt:
            switch await prompt(origin, destinationURL, spaceName) {
            case .open:
                opensExternalURL(destinationURL)
            case .openAndRemember:
                permissionCenter.setDecision(
                    .grantPersistently,
                    for: .externalApplications,
                    origin: origin,
                    detail: scheme,
                    in: spaceID
                )
                opensExternalURL(destinationURL)
            case .cancel:
                return
            }
        }
    }
}
