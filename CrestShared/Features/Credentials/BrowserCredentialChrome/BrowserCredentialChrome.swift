import SwiftUI

/// The credential prompt a page is presenting, on every shell.
///
/// Which prompt that is comes from `BrowserCredentialChromePresentation`, what
/// each prompt can do to the page comes from the two ports, and how each one is
/// drawn comes from what the shell says it can do. Nothing about the chrome is
/// left for a shell to decide twice — including where it goes, which is why the
/// profile is resolved here rather than three times over inside the prompts.
struct BrowserCredentialChrome: View {
    let presentation: BrowserCredentialChromePresentation
    let fillPort: BrowserCredentialFillPort
    let savePort: BrowserCredentialSavePort
    let browser: BrowserStore
    let capabilities: BrowserInteractionCapabilities

    /// The quiet request whose site the Space has logins for, once known.
    @State private var revealedQuietRequestID: UUID?

    /// The saved login a candidate that named no account was found to be for,
    /// once known.
    @State private var namedAccount: (candidateID: UUID, account: CredentialDescriptor)?

    var body: some View {
        ZStack {
            // On screen even while nothing shows, so the checks a held-back
            // prompt waits on run before it appears.
            Color.clear
                .frame(width: 0, height: 0)
                .task(id: quietRequest?.id) {
                    await revealQuietRequest()
                }
                .task(id: anonymousCandidate?.id) {
                    await nameAccount()
                }
            BrowserCredentialChromePlacement(
                field: anchoredField,
                metrics: BrowserCredentialPromptMetrics.resolve(capabilities)
            ) { metrics in
                prompt(metrics)
            }
        }
    }

    /// A save candidate from a password change that named no account.
    private var anonymousCandidate: BrowserCredentialSaveCandidate? {
        guard case .save(let candidate) = presentation, candidate.needsAccount else { return nil }
        return candidate
    }

    /// A fill request from a username field, which shows only when the Space
    /// has logins for its site.
    private var quietRequest: BrowserCredentialFillRequest? {
        guard case .suggestions(let request) = presentation, request.isQuietWithoutLogins else { return nil }
        return request
    }

    /// The prompt on show: the presentation, unless it is a quiet request not
    /// yet known to have logins, which shows nothing and takes no room.
    private var shownPresentation: BrowserCredentialChromePresentation {
        if let quietRequest, revealedQuietRequestID != quietRequest.id { return .none }
        if let anonymousCandidate {
            guard let namedAccount, namedAccount.candidateID == anonymousCandidate.id else { return .none }
            return .save(anonymousCandidate.naming(namedAccount.account))
        }
        return presentation
    }

    /// Names the account of a password change from the saved login whose
    /// password the form's current password is; with none, nothing is saved.
    private func nameAccount() async {
        guard let candidate = anonymousCandidate else { return }
        let account = try? await browser.accountHoldingCurrentPassword(of: candidate, in: savePort.spaceID)
        guard !Task.isCancelled, anonymousCandidate?.id == candidate.id else { return }
        if let account {
            namedAccount = (candidate.id, account)
        } else {
            savePort.dismiss()
        }
    }

    private func revealQuietRequest() async {
        guard let request = quietRequest else { return }
        let logins = (try? await browser.credentialSuggestions(for: request.origin, in: fillPort.spaceID)) ?? []
        guard !Task.isCancelled, quietRequest?.id == request.id else { return }
        if logins.isEmpty {
            fillPort.dismiss()
        } else {
            revealedQuietRequestID = request.id
        }
    }

    /// Where the field that raised this prompt sits over the page, in this
    /// shell's points, or `nil` where the prompt is not anchored to one.
    ///
    /// The page reports CSS pixels from its own viewport, and the page's zoom
    /// is the whole of the difference between those and what is on screen —
    /// the chrome is drawn in the web view's own box, so nothing else has to
    /// be undone.
    private var anchoredField: CGRect? {
        guard let rect = shownPresentation.fillRequest?.fieldRect else { return nil }
        let scale = fillPort.contentScale
        guard scale.isFinite, scale > 0 else { return nil }
        return CGRect(
            x: rect.x * scale,
            y: rect.y * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
    }

    @ViewBuilder
    private func prompt(
        _ metrics: BrowserCredentialPromptMetrics
    ) -> some View {
        switch shownPresentation {
        case .none:
            EmptyView()
        case .save(let candidate):
            BrowserCredentialSavePrompt(
                candidate: candidate,
                port: savePort,
                browser: browser,
                metrics: metrics
            )
        case .strongPassword(let request):
            BrowserStrongPasswordPrompt(
                request: request,
                port: fillPort,
                browser: browser,
                metrics: metrics
            )
        case .suggestions(let request):
            BrowserCredentialSuggestionPrompt(
                request: request,
                port: fillPort,
                browser: browser,
                metrics: metrics
            )
        }
    }
}
