import Foundation

/// Signing an agent in with a login the person saved in Crest Passwords,
/// which Crest fills itself, so the agent never reads the password. The fill
/// goes the way a person's does: the agent focuses a field of the sign-in
/// form, the page's credential bridge asks Crest to fill the form, and Crest
/// fills the login the person chooses, asking every time. It works only while
/// the person lets agents sign in and doesn't let them run scripts in pages,
/// which could read what was filled, and only on a secure page's own form in
/// a Space whose Crest Passwords fills.
extension BrowserMacAgents {
    // MARK: - Types

    private struct SignIn: Decodable {
        let tab: UUID
        let uid: String
    }

    /// Where the field the agent focused is in the viewport, in CSS pixels,
    /// and whether it took the focus.
    private struct FocusedField: Decodable {
        let x: Double
        let y: Double
        let focused: Bool
    }

    // MARK: - Static Variables

    /// How long the page is given to ask Crest to fill the form whose field
    /// the agent focused.
    private static let fillRequestTimeout = Duration.seconds(2)

    // MARK: - Actions - Sign-in

    func fillCredential(_ call: BrowserAgentCall) async throws(BrowserAgentFailure) -> AgentToolResult {
        let signIn = try call.arguments(SignIn.self)
        try allowsSignIn()
        return try await serially(on: signIn.tab) { () async throws(BrowserAgentFailure) -> AgentToolResult in
            let page = try await self.settledPage(for: signIn.tab, call)
            try self.fillsPasswords(on: page)
            let request = try await self.signInRequest(for: signIn.uid, on: page)
            // The popup the request shows the person goes with it, however
            // the fill ends.
            defer {
                if page.credentialFillRequest?.id == request.id { page.dismissCredentialFillRequest() }
            }
            try self.check(request, on: page)
            let logins = await self.savedLogins(for: request, on: page)
            guard !logins.isEmpty else { throw .noSavedLogin }
            let agentName = try self.allowedName(of: try self.connectedSession(call))
            let chosen = try await self.approvals.approve(
                BrowserAgentSignIn(agentName: agentName, site: request.origin.host, logins: logins),
                for: ObjectIdentifier(call.link))
            // The person may stop allowing it, lock the Space or use the form
            // themselves while asked.
            try self.allowsSignIn()
            guard try self.page(for: signIn.tab, call) === page, page.credentialFillRequest?.id == request.id else {
                throw .signInChanged
            }
            try self.fillsPasswords(on: page)
            guard logins.contains(where: { $0.id == chosen }),
                let credential = try? await self.application.browser.credential(id: chosen, in: page.spaceID)
            else { throw .signInChanged }
            do {
                try await page.fillCredential(credential, for: request.id)
            } catch {
                throw .signInChanged
            }
            // A username step's login fills no password step by itself for an
            // agent; the person is asked again.
            page.credentialState.forgetChosenAccount()
            self.note(.filledPassword, request.origin.host, call)
            return .message("Filled the saved login. Crest doesn’t give you its password.")
        }
    }

    /// Refuses unless the person lets agents sign in with saved passwords and
    /// doesn't let them run scripts in pages, which could read a filled
    /// password.
    private func allowsSignIn() throws(BrowserAgentFailure) {
        let preferences = core.state.agentPreferences
        guard preferences.fillsPasswords else { throw .signInOff }
        guard !preferences.runsScripts else { throw .signInWithScripts }
    }

    /// Refuses unless Crest Passwords fills on `page`: on in its Space, not
    /// left to an extension, and on a page served over HTTPS.
    private func fillsPasswords(on page: BrowserPage) throws(BrowserAgentFailure) {
        guard page.isCredentialAccessEnabled,
            let access = try? application.browser.credentialAccess(.fill, in: page.spaceID), access.refusal == nil
        else { throw .passwordsOff }
        guard !page.credentialState.passwordsHandledElsewhere else { throw .passwordsElsewhere }
        guard Self.origin(of: page)?.isSecure == true else { throw .insecurePage }
    }

    /// The request the page's credential bridge makes once the agent focuses
    /// the field `uid` names, as a person's click on it would; never one made
    /// before.
    private func signInRequest(for uid: String, on page: BrowserPage) async throws(BrowserAgentFailure)
        -> BrowserCredentialFillRequest
    {
        let earlier = page.credentialFillRequest?.id
        let answer = try await run(BrowserAgentPageScript.focusSignIn(uid), on: page)
        guard answer["error"] == nil, let field = try? answer.decoded(as: FocusedField.self) else {
            throw .unknownElement(uid)
        }
        page.pointAgent(at: PagePoint(x: field.x, y: field.y), presses: true)
        guard field.focused else { throw .notSignInField }
        let deadline = ContinuousClock.now + Self.fillRequestTimeout
        repeat {
            if let request = page.credentialFillRequest, request.id != earlier { return request }
            try? await Task.sleep(for: .milliseconds(50))
        } while ContinuousClock.now < deadline
        throw .notSignInField
    }

    /// Refuses a request a saved login doesn't fill, or one that isn't for
    /// the tab's own page, such as a frame's from another site, or that
    /// Crest Passwords doesn't fill for its origin.
    private func check(_ request: BrowserCredentialFillRequest, on page: BrowserPage) throws(BrowserAgentFailure) {
        guard request.takesSavedLogin else { throw .notSignInField }
        guard !request.isCrossOriginFrame, request.origin == request.topLevelOrigin,
            Self.origin(of: page) == request.topLevelOrigin
        else { throw .otherSiteField }
        guard request.origin.isSecure else { throw .insecurePage }
        guard let access = try? application.browser.credentialAccess(.fill, in: page.spaceID, origin: request.origin),
            access.refusal == nil
        else { throw .passwordsOff }
    }

    /// The logins `page`'s own Space keeps for exactly the request's site,
    /// which are the ones its fill takes: a login that only names the site
    /// among others or spells it another way, or that another Space of its
    /// group keeps, is left out.
    private func savedLogins(for request: BrowserCredentialFillRequest, on page: BrowserPage) async
        -> [CredentialDescriptor]
    {
        let suggestions = try? await application.browser.credentialSuggestions(for: request.origin, in: page.spaceID)
        return (suggestions ?? []).filter { $0.spaceID == page.spaceID && $0.origin == request.origin }
    }

    /// The origin of the document `page` shows now.
    private static func origin(of page: BrowserPage) -> CredentialOrigin? {
        page.live.url.flatMap(URL.init(string:)).flatMap(CredentialOrigin.init(url:))
    }
}
