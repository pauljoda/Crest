import Foundation

/// Shared authentication and permission prompt handling for both macOS and
/// iOS/iPadOS pages. Each platform supplies only its native HTTP auth sheet or
/// alert presenter (`presentHTTPAuthenticationPrompt(_:dismissal:)`).
extension BrowserPlatformPage {
    // MARK: - Actions - Prompts

    func ask(_ asked: AuthenticationAsked, dismissal: BrowserPromptDismissal) {
        let corePage = corePage
        let promptID = asked.promptID
        guard let challenge = BrowserAuthenticationChallenge(asked.question) else {
            corePage.answer(AnswerAuthentication(promptID: promptID, credential: nil))
            return
        }
        let session = httpAuthenticationSession
        Task { @MainActor [weak self] in
            let decision = await session.response(to: challenge) { prompt in
                await self?.presentHTTPAuthenticationPrompt(prompt, dismissal: dismissal)
            }
            corePage.answer(AnswerAuthentication(promptID: promptID, credential: decision.credential))
        }
    }

    func ask(_ asked: PermissionAsked, dismissal: BrowserPromptDismissal) {
        let question = asked.question
        let corePage = corePage
        let promptID = asked.promptID
        let requests = sitePermissionRequests
        let spaceName = spaceName
        Task { @MainActor [weak self] in
            var response = await requests.response(
                to: question.permission, origin: question.origin, topLevelOrigin: question.topLevelOrigin,
                spaceName: spaceName, dismissal: dismissal)
            // An Allow the system then refuses saves nothing, so the site
            // cannot gain the capability silently once the system allows it.
            if response.grants, await self?.systemConsent.consents(to: question.permission) != true {
                response = .denyOnce
            }
            corePage.answer(
                AnswerPermission(promptID: promptID, grants: response.grants, remembers: response.savedDecision != nil))
        }
    }
}
